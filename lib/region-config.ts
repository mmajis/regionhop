import * as fs from 'fs';
import * as path from 'path';

export interface RegionConfig {
  defaultRegion: string;
  vpnSubnetIpv4?: string;
  vpnSubnetIpv6?: string;
  vpnPort: number;
  domain?: string;
  hostedZoneId?: string;
  dnsRecordTtl?: number;
  deploymentId?: string;
}

let regionConfig: RegionConfig | null = null;

/**
 * Load region configuration from config.json
 */
function loadRegionConfig(): RegionConfig {
  if (!regionConfig) {
    const configPath = path.join(__dirname, '..', 'config.json');
    const configData = fs.readFileSync(configPath, 'utf8');
    regionConfig = JSON.parse(configData);
  }
  return regionConfig!;
}

/**
 * Get the default region
 */
export function getDefaultRegion(): string {
  return loadRegionConfig().defaultRegion;
}

/**
 * Get VPN IPv4 subnet configuration
 */
export function getVpnSubnetIpv4(): string | undefined {
  return loadRegionConfig().vpnSubnetIpv4;
}

/**
 * Get VPN IPv6 subnet configuration
 */
export function getVpnSubnetIpv6(): string | undefined {
  return loadRegionConfig().vpnSubnetIpv6;
}

/**
 * Check if IPv4 VPN subnet is configured
 */
export function hasVpnSubnetIpv4(): boolean {
  const ipv4Subnet = getVpnSubnetIpv4();
  return ipv4Subnet !== undefined && ipv4Subnet !== null && ipv4Subnet.trim() !== '';
}

/**
 * Check if IPv6 VPN subnet is configured
 */
export function hasVpnSubnetIpv6(): boolean {
  const ipv6Subnet = getVpnSubnetIpv6();
  return ipv6Subnet !== undefined && ipv6Subnet !== null && ipv6Subnet.trim() !== '';
}

/**
 * Get VPN port configuration
 */
export function getVpnPort(): number {
  return loadRegionConfig().vpnPort;
}

/**
 * Get region from environment variable or default
 */
export function getTargetRegion(): string {
  const envRegion = process.env.REGIONHOP_REGION;
  if (envRegion) {
    return envRegion;
  }
  return getDefaultRegion();
}

/**
 * Get region-aware stack name
 */
export function getStackName(baseName: string, region: string): string {
  return `RegionHop-${region}-${baseName}`;
}

/**
 * Get region-aware export name
 */
export function getExportName(baseName: string, region: string): string {
  return `RegionHop-${region}-${baseName}`;
}

/**
 * Get region-aware resource name
 */
export function getResourceName(baseName: string, region: string): string {
  return `${baseName}-${region}`;
}



/**
 * Get domain configuration from environment or config file
 */
export function getDomain(): string | undefined {
  const envDomain = process.env.REGIONHOP_DOMAIN;
  if (envDomain) {
    return envDomain;
  }

  const config = loadRegionConfig();
  return config.domain;
}

/**
 * Get hosted zone ID from environment or config file
 */
export function getHostedZoneId(): string | undefined {
  const envHostedZoneId = process.env.REGIONHOP_HOSTED_ZONE_ID;
  if (envHostedZoneId) {
    return envHostedZoneId;
  }

  const config = loadRegionConfig();
  return config.hostedZoneId;
}

/**
 * Get DNS record TTL from environment or config file
 */
export function getDnsRecordTtl(): number {
  const envTtl = process.env.REGIONHOP_DNS_TTL;
  if (envTtl) {
    return parseInt(envTtl, 10);
  }

  const config = loadRegionConfig();
  return config.dnsRecordTtl || 30; // Default 30 seconds for quick failover
}

/**
 * Generate VPN subdomain for a region
 */
export function getVpnSubdomain(region: string): string {
  const domain = getDomain();
  return `${region}.regionhop.${domain}`;
}

/**
 * Check if DNS management is enabled
 */
export function isDnsManagementEnabled(): boolean {
  const envDisabled = process.env.REGIONHOP_DISABLE_DNS;
  if (envDisabled && envDisabled.toLowerCase() === 'true') {
    return false;
  }
  if (getDomain() === undefined || getDomain() === '') {
    return false;
  }

  return true;
}

/**
 * Get deployment ID from environment or config file
 * This ensures S3 bucket names are unique across different deployments
 */
export function getDeploymentId(): string {
  const envDeploymentId = process.env.REGIONHOP_DEPLOYMENT_ID;
  if (envDeploymentId) {
    return envDeploymentId;
  }

  const config = loadRegionConfig();
  return config.deploymentId || 'default';
}