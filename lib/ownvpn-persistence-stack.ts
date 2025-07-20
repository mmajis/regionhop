import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';
import { getExportName, getResourceName, getDeploymentId } from './region-config';

export class OwnvpnPersistenceStack extends cdk.Stack {
  public readonly wireguardStateBackupBucket: s3.Bucket;
  public readonly bucketKmsKey: kms.Key;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Get the target region from the stack's environment
    const targetRegion = this.region;
    const deploymentId = getDeploymentId();

    // Create KMS key for S3 bucket encryption
    this.bucketKmsKey = new kms.Key(this, 'WireGuardStateBackupKmsKey', {
      description: `KMS key for WireGuard state backup encryption - ${targetRegion} (${deploymentId})`,
      enableKeyRotation: true,
      alias: `${getResourceName('wireguard-backup-key', targetRegion)}-${deploymentId}`,
      policy: new iam.PolicyDocument({
        statements: [
          // Allow root account access for key administration
          new iam.PolicyStatement({
            sid: 'Enable IAM User Permissions',
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['kms:*'],
            resources: ['*'],
          }),
          // Allow CloudTrail to use the key for encryption
          new iam.PolicyStatement({
            sid: 'Allow CloudTrail encryption',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('cloudtrail.amazonaws.com')],
            actions: [
              'kms:GenerateDataKey*',
              'kms:DescribeKey',
            ],
            resources: ['*'],
          }),
        ],
      }),
    });

    // Create S3 bucket for WireGuard state backup with comprehensive security
    this.wireguardStateBackupBucket = new s3.Bucket(this, 'WireGuardStateBackupBucket', {
      bucketName: `${getResourceName('wireguard-state-backup', targetRegion)}-${deploymentId}`.toLowerCase(),
      
      // Encryption configuration
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: this.bucketKmsKey,
      bucketKeyEnabled: true, // Reduces KMS costs by using S3 Bucket Keys

      // Block all public access
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      
      // Enable versioning for data protection
      versioned: true,
      
      // Lifecycle management for cost optimization
      lifecycleRules: [
        {
          id: 'WireGuardStateBackupLifecycle',
          enabled: true,
          // Keep current version for 90 days, then transition to IA
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
          // Keep non-current versions for 30 days, then delete
          noncurrentVersionTransitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(7),
            },
          ],
          noncurrentVersionExpiration: cdk.Duration.days(30),
          // Delete incomplete multipart uploads after 7 days
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
      ],

      // Enable access logging (optional - can be enabled if needed for compliance)
      // Note: This would require another bucket for logs, adding cost
      // serverAccessLogsPrefix: 'access-logs/',

      // CORS configuration - restrictive for security
      cors: [
        {
          allowedMethods: [s3.HttpMethods.GET, s3.HttpMethods.PUT, s3.HttpMethods.POST],
          allowedOrigins: ['*'], // This should be more restrictive in production
          allowedHeaders: ['*'],
          maxAge: 3000,
        },
      ],

      // Enable event notifications (can be used for monitoring)
      eventBridgeEnabled: true,

      // Enforce SSL/TLS for all requests
      enforceSSL: true,

      // Removal policy - retain for production safety
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // Create IAM policy for EC2 instances to access the backup bucket
    const bucketAccessPolicy = new iam.ManagedPolicy(this, 'WireGuardBucketAccessPolicy', {
      managedPolicyName: `${getResourceName('wireguard-bucket-access', targetRegion)}-${deploymentId}`,
      description: `IAM policy for WireGuard EC2 instances to access state backup bucket - ${targetRegion} (${deploymentId})`,
      statements: [
        // S3 bucket permissions
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:GetObject',
            's3:PutObject',
            's3:DeleteObject',
            's3:ListBucket',
            's3:GetBucketLocation',
          ],
          resources: [
            this.wireguardStateBackupBucket.bucketArn,
            `${this.wireguardStateBackupBucket.bucketArn}/*`,
          ],
        }),
        // KMS permissions for bucket encryption/decryption
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'kms:Decrypt',
            'kms:GenerateDataKey',
            'kms:DescribeKey',
          ],
          resources: [this.bucketKmsKey.keyArn],
        }),
      ],
    });

    // Outputs for cross-stack references
    new cdk.CfnOutput(this, 'WireGuardStateBackupBucketName', {
      value: this.wireguardStateBackupBucket.bucketName,
      description: `WireGuard state backup bucket name - ${targetRegion}`,
      exportName: getExportName('StateBackupBucket-Name', targetRegion),
    });

    new cdk.CfnOutput(this, 'WireGuardStateBackupBucketArn', {
      value: this.wireguardStateBackupBucket.bucketArn,
      description: `WireGuard state backup bucket ARN - ${targetRegion}`,
      exportName: getExportName('StateBackupBucket-ARN', targetRegion),
    });

    new cdk.CfnOutput(this, 'BucketAccessPolicyArn', {
      value: bucketAccessPolicy.managedPolicyArn,
      description: `IAM policy ARN for bucket access - ${targetRegion}`,
      exportName: getExportName('BucketAccessPolicy-ARN', targetRegion),
    });

    new cdk.CfnOutput(this, 'BucketKmsKeyId', {
      value: this.bucketKmsKey.keyId,
      description: `KMS key ID for bucket encryption - ${targetRegion}`,
      exportName: getExportName('BucketKmsKey-ID', targetRegion),
    });

    new cdk.CfnOutput(this, 'BucketKmsKeyArn', {
      value: this.bucketKmsKey.keyArn,
      description: `KMS key ARN for bucket encryption - ${targetRegion}`,
      exportName: getExportName('BucketKmsKey-ARN', targetRegion),
    });

    // Output commands for manual backup/restore operations
    new cdk.CfnOutput(this, 'BackupCommand', {
      value: `aws s3 sync /etc/wireguard s3://${this.wireguardStateBackupBucket.bucketName}/wireguard-config/ --exclude "*.tmp" --delete --region ${targetRegion}`,
      description: 'Command to backup WireGuard configuration to S3',
    });

    new cdk.CfnOutput(this, 'RestoreCommand', {
      value: `aws s3 sync s3://${this.wireguardStateBackupBucket.bucketName}/wireguard-config/ /etc/wireguard --delete --region ${targetRegion}`,
      description: 'Command to restore WireGuard configuration from S3',
    });

    new cdk.CfnOutput(this, 'SecurityNote', {
      value: 'This bucket contains sensitive WireGuard private keys. Ensure proper IAM permissions and monitor access.',
      description: 'Important security reminder',
    });
  }
}