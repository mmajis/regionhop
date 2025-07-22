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
  
  if (!domainName) {
    console.error('Missing required environment variables');
    return { statusCode: 400, body: 'Missing required environment variables' };
  }
  
  try {
    // Only handle successful instance launches
    if (statusCode === 'InProgress' || statusCode === 'Successful') {
      if (ec2InstanceId) {
        console.log(`Processing instance launch: ${ec2InstanceId}`);
        
        // Wait a bit for instance to be fully ready
        await new Promise(resolve => setTimeout(resolve, 10000));
        
        // Get instance public IP and update DNS record
        const publicIp = await getInstancePublicIp(ec2InstanceId);
        await updateDnsRecord(domainName, publicIp, hostedZoneId, dnsRecordTtl);
        
        console.log(`Successfully updated DNS for ${domainName} -> ${publicIp}`);
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

async function getInstancePublicIp(instanceId: string): Promise<string> {
  try {
    const command = new DescribeInstancesCommand({
      InstanceIds: [instanceId],
    });
    
    const result = await ec2Client.send(command);
    
    if (result.Reservations && result.Reservations.length > 0) {
      const instance = result.Reservations[0].Instances?.[0];
      if (instance?.PublicIpAddress) {
        console.log(`Found public IP ${instance.PublicIpAddress} for instance ${instanceId}`);
        return instance.PublicIpAddress;
      }
    }
    
    throw new Error(`Could not find public IP for instance: ${instanceId}`);
  } catch (error) {
    console.error(`Failed to get instance public IP: ${error}`);
    throw error;
  }
}

async function updateDnsRecord(
  domainName: string,
  publicIp: string,
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
    
    // Update DNS record
    const changeParams = {
      HostedZoneId: zoneId,
      ChangeBatch: {
        Changes: [
          {
            Action: ChangeAction.UPSERT,
            ResourceRecordSet: {
              Name: domainName,
              Type: 'A' as const,
              TTL: ttl,
              ResourceRecords: [
                {
                  Value: publicIp,
                },
              ],
            },
          },
        ],
      },
    };
    
    const command = new ChangeResourceRecordSetsCommand(changeParams);
    const result = await route53Client.send(command);
    
    console.log(`DNS record updated for ${domainName} -> ${publicIp} (TTL: ${ttl}s)`);
    console.log(`Change ID: ${result.ChangeInfo?.Id}`);
  } catch (error) {
    console.error(`Failed to update DNS record: ${error}`);
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