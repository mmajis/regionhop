import { Handler, EventBridgeEvent } from 'aws-lambda';
import { EC2Client, DescribeInstancesCommand } from '@aws-sdk/client-ec2';
import { Route53Client, ChangeResourceRecordSetsCommand, ListHostedZonesByNameCommand, ChangeAction } from '@aws-sdk/client-route-53';
import { AutoScalingClient, DescribeAutoScalingGroupsCommand } from '@aws-sdk/client-auto-scaling';

interface ASGEvent {
  source: string;
  'detail-type': string;
  detail: {
    StatusCode: string;
    StatusMessage: string;
    AutoScalingGroupName: string;
    ActivityId: string;
    AccountId: string;
    RequestId: string;
    StatusMessageParsed: string;
    AutoScalingGroupARN: string;
    ActivityDetails: string;
    EC2InstanceId?: string;
  };
}

const ec2Client = new EC2Client({});
const route53Client = new Route53Client({});
const autoscalingClient = new AutoScalingClient({});

export const handler: Handler<EventBridgeEvent<string, any>> = async (event) => {
  console.log('Received event:', JSON.stringify(event, null, 2));

  const { detail } = event;
  const autoScalingGroupName = detail.AutoScalingGroupName;
  const statusCode = detail.StatusCode;
  const ec2InstanceId = detail.EC2InstanceId;

  // Get environment variables
  const domainName = process.env.DOMAIN_NAME;
  const hostedZoneId = process.env.HOSTED_ZONE_ID;
  const dnsRecordTtl = parseInt(process.env.DNS_RECORD_TTL || '30', 10);
  const hasIpv4Subnet = process.env.HAS_IPV4_SUBNET === 'true';
  const hasIpv6Subnet = process.env.HAS_IPV6_SUBNET === 'true';

  if (!domainName) {
    console.error('Missing required environment variables');
    return { statusCode: 400, body: 'Missing required environment variables' };
  }

  console.log(`DNS configuration - IPv4: ${hasIpv4Subnet}, IPv6: ${hasIpv6Subnet}`);

  try {
    // Only handle successful instance launches
    if (statusCode === 'InProgress' || statusCode === 'Successful') {
      if (ec2InstanceId) {
        console.log(`Processing instance launch: ${ec2InstanceId}`);

        // Wait a bit for instance to be fully ready
        await new Promise(resolve => setTimeout(resolve, 10000));

        // Get instance addresses based on configuration
        const addresses = await getInstanceAddresses(ec2InstanceId, hasIpv4Subnet, hasIpv6Subnet);
        await updateDnsRecords(domainName, addresses, hostedZoneId, dnsRecordTtl);

        console.log(`Successfully updated DNS for ${domainName}:`, addresses);
      }
    } else if (statusCode === 'Failed') {
      console.log(`Instance launch failed for ASG: ${autoScalingGroupName}`);
    }

    return { statusCode: 200, body: 'DNS update completed' };
  } catch (error) {
    console.error('Error updating DNS:', error);
    return { statusCode: 500, body: `Error: ${error}` };
  }
};

interface InstanceAddresses {
  ipv4?: string;
  ipv6?: string;
}

async function getInstanceAddresses(instanceId: string, needsIpv4: boolean, needsIpv6: boolean): Promise<InstanceAddresses> {
  try {
    const command = new DescribeInstancesCommand({
      InstanceIds: [instanceId],
    });

    const result = await ec2Client.send(command);
    const addresses: InstanceAddresses = {};

    if (result.Reservations && result.Reservations.length > 0) {
      const instance = result.Reservations[0].Instances?.[0];

      // Get IPv4 address if needed
      if (needsIpv4) {
        if (instance?.PublicIpAddress) {
          addresses.ipv4 = instance.PublicIpAddress;
          console.log(`Found public IPv4 ${instance.PublicIpAddress} for instance ${instanceId}`);
        } else {
          console.warn(`No public IPv4 found for instance ${instanceId}`);
        }
      }

      // Get IPv6 address if needed
      if (needsIpv6) {
        // Check for IPv6 address
        if (instance?.Ipv6Address) {
          addresses.ipv6 = instance.Ipv6Address;
          console.log(`Found public IPv6 ${instance.Ipv6Address} for instance ${instanceId}`);
        } else if (instance?.NetworkInterfaces) {
          // Check NetworkInterfaces for IPv6 addresses
          for (const ni of instance.NetworkInterfaces) {
            if (ni.Ipv6Addresses && ni.Ipv6Addresses.length > 0) {
              const ipv6 = ni.Ipv6Addresses[0].Ipv6Address;
              if (ipv6) {
                addresses.ipv6 = ipv6;
                console.log(`Found IPv6 ${ipv6} for instance ${instanceId}`);
                break;
              }
            }
          }
        }
        
        if (!addresses.ipv6) {
          console.warn(`No public IPv6 found for instance ${instanceId}`);
        }
      }
    }

    // Ensure we found at least one required address
    if ((needsIpv4 && !addresses.ipv4) && (needsIpv6 && !addresses.ipv6)) {
      throw new Error(`Could not find any required IP addresses for instance: ${instanceId}`);
    }

    return addresses;
  } catch (error) {
    console.error(`Failed to get instance addresses: ${error}`);
    throw error;
  }
}

async function updateDnsRecords(
  domainName: string,
  addresses: InstanceAddresses,
  hostedZoneId?: string,
  ttl: number = 30
): Promise<void> {
  try {
    // Find hosted zone if not provided
    let zoneId = hostedZoneId;
    if (!zoneId) {
      zoneId = await findHostedZoneId(domainName);
    }

    if (!zoneId) {
      throw new Error(`Could not find hosted zone for domain: ${domainName}`);
    }

    const changes: any[] = [];

    // Add A record for IPv4 if available
    if (addresses.ipv4) {
      changes.push({
        Action: ChangeAction.UPSERT,
        ResourceRecordSet: {
          Name: domainName,
          Type: 'A' as const,
          TTL: ttl,
          ResourceRecords: [
            {
              Value: addresses.ipv4,
            },
          ],
        },
      });
      console.log(`Preparing A record: ${domainName} -> ${addresses.ipv4}`);
    }

    // Add AAAA record for IPv6 if available
    if (addresses.ipv6) {
      changes.push({
        Action: ChangeAction.UPSERT,
        ResourceRecordSet: {
          Name: domainName,
          Type: 'AAAA' as const,
          TTL: ttl,
          ResourceRecords: [
            {
              Value: addresses.ipv6,
            },
          ],
        },
      });
      console.log(`Preparing AAAA record: ${domainName} -> ${addresses.ipv6}`);
    }

    if (changes.length === 0) {
      console.warn('No DNS records to update - no valid IP addresses found');
      return;
    }

    // Update DNS records
    const changeParams = {
      HostedZoneId: zoneId,
      ChangeBatch: {
        Changes: changes,
      },
    };

    const command = new ChangeResourceRecordSetsCommand(changeParams);
    const result = await route53Client.send(command);

    console.log(`DNS records updated for ${domainName} (TTL: ${ttl}s):`);
    if (addresses.ipv4) console.log(`  A record: ${addresses.ipv4}`);
    if (addresses.ipv6) console.log(`  AAAA record: ${addresses.ipv6}`);
    console.log(`Change ID: ${result.ChangeInfo?.Id}`);
  } catch (error) {
    console.error(`Failed to update DNS records: ${error}`);
    throw error;
  }
}


async function findHostedZoneId(domainName: string): Promise<string | undefined> {
  try {
    // Extract the root domain from the subdomain
    const domainParts = domainName.split('.');
    let rootDomain = domainName;

    if (domainParts.length > 2) {
      rootDomain = domainParts.slice(-2).join('.');
    }

    const command = new ListHostedZonesByNameCommand({
      DNSName: rootDomain,
    });

    const result = await route53Client.send(command);

    if (result.HostedZones && result.HostedZones.length > 0) {
      // Find exact match for the root domain
      const zone = result.HostedZones.find(z => z.Name === `${rootDomain}.`);
      return zone?.Id?.replace('/hostedzone/', '');
    }

    return undefined;
  } catch (error) {
    console.error(`Failed to find hosted zone: ${error}`);
    return undefined;
  }
}