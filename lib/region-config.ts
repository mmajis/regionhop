import * as fs from 'fs';
import * as path from 'path';

export interface RegionInfo {
  code: string;
  name: string;
  description: string;
}

export interface RegionConfig {
  supportedRegions: RegionInfo[];
  defaultRegion: string;
  vpnSubnet: string;
  vpnPort: number;
  domain?: string;
  hostedZoneId?: string;
  dnsRecordTtl?: number;
  deploymentId?: string;
}

let regionConfig: RegionConfig | null = null;

/**
 * Load region configuration from regions.json
 */
function loadRegionConfig(): RegionConfig {
  if (!regionConfig) {
    const configPath = path.join(__dirname, '..', 'regions.json');
    const configData = fs.readFileSync(configPath, 'utf8');
    regionConfig = JSON.parse(configData);
  }
  return regionConfig!;
}

/**
 * Get all supported regions
 */
export function getSupportedRegions(): RegionInfo[] {
  return loadRegionConfig().supportedRegions;
}

/**
 * Get the default region
 */
export function getDefaultRegion(): string {
  return loadRegionConfig().defaultRegion;
}

/**
 * Get VPN subnet configuration
 */
export function getVpnSubnet(): string {
  return loadRegionConfig().vpnSubnet;
}

/**
 * Get VPN port configuration
 */
export function getVpnPort(): number {
  return loadRegionConfig().vpnPort;
}

/**
 * Validate if a region is supported
 */
export function isRegionSupported(region: string): boolean {
  const supportedRegions = getSupportedRegions();
  return supportedRegions.some(r => r.code === region);
}

/**
 * Get region from environment variable or default
 */
export function getTargetRegion(): string {
  const envRegion = process.env.VPN_REGION;
  if (envRegion) {
    if (!isRegionSupported(envRegion)) {
      throw new Error(`Unsupported region: ${envRegion}. Supported regions: ${getSupportedRegions().map(r => r.code).join(', ')}`);
    }
    return envRegion;
  }
  return getDefaultRegion();
}

/**
 * Get region-aware stack name
 */
export function getStackName(baseName: string, region: string): string {
  return `OwnVPN-${region}-${baseName}`;
}

/**
 * Get region-aware export name
 */
export function getExportName(baseName: string, region: string): string {
  return `OwnVPN-${region}-${baseName}`;
}

/**
 * Get region-aware resource name
 */
export function getResourceName(baseName: string, region: string): string {
  return `${baseName}-${region}`;
}

/**
 * Get region info by code
 */
export function getRegionInfo(regionCode: string): RegionInfo | undefined {
  return getSupportedRegions().find(r => r.code === regionCode);
}

/**
 * Validate region and throw error if not supported
 */
export function validateRegion(region: string): void {
  if (!isRegionSupported(region)) {
    const supportedRegions = getSupportedRegions().map(r => r.code).join(', ');
    throw new Error(`Unsupported region: ${region}. Supported regions: ${supportedRegions}`);
  }
}

/**
 * Get domain configuration from environment or config file
 */
export function getDomain(): string {
  const envDomain = process.env.VPN_DOMAIN;
  if (envDomain) {
    return envDomain;
  }

  const config = loadRegionConfig();
  return config.domain || 'majakorpi.net';
}

/**
 * Get hosted zone ID from environment or config file
 */
export function getHostedZoneId(): string | undefined {
  const envHostedZoneId = process.env.VPN_HOSTED_ZONE_ID;
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
  const envTtl = process.env.VPN_DNS_TTL;
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
  return `${region}.vpn.${domain}`;
}

/**
 * Check if DNS management is enabled
 */
export function isDnsManagementEnabled(): boolean {
  const envDisabled = process.env.VPN_DISABLE_DNS;
  if (envDisabled && envDisabled.toLowerCase() === 'true') {
    return false;
  }

  // DNS management is enabled by default
  return true;
}

/**
 * Get deployment ID from environment or config file
 * This ensures S3 bucket names are unique across different deployments
 */
export function getDeploymentId(): string {
  const envDeploymentId = process.env.VPN_DEPLOYMENT_ID;
  if (envDeploymentId) {
    return envDeploymentId;
  }

  const config = loadRegionConfig();
  return config.deploymentId || 'default';
}