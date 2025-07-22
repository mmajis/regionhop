import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';
import { getExportName, getResourceName, getDeploymentId } from './region-config';

export class RegionHopPersistenceStack extends cdk.Stack {
  public readonly stateBackupBucket: s3.Bucket;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Get the target region from the stack's environment
    const targetRegion = this.region;
    const deploymentId = getDeploymentId();

    // Create S3 bucket for state backup with comprehensive security
    this.stateBackupBucket = new s3.Bucket(this, 'StateBackupBucket', {
      bucketName: `${getResourceName('regionhop-state-backup', targetRegion)}-${deploymentId}`.toLowerCase(),

      // Encryption configuration
      encryption: s3.BucketEncryption.S3_MANAGED,

      // Block all public access
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,

      // Enable versioning for data protection
      versioned: true,

      // Lifecycle management for cost optimization
      lifecycleRules: [
        {
          id: 'StateBackupLifecycle',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(90),
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
      ],

      // Enforce SSL/TLS for all requests
      enforceSSL: true,

      // Removal policy - retain for production safety
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // Create IAM policy for EC2 instances to access the backup bucket
    const bucketAccessPolicy = new iam.ManagedPolicy(this, 'BucketAccessPolicy', {
      managedPolicyName: `${getResourceName('regionhop-bucket-access', targetRegion)}-${deploymentId}`,
      description: `IAM policy for RegionHop EC2 instances to access state backup bucket - ${targetRegion} (${deploymentId})`,
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
            this.stateBackupBucket.bucketArn,
            `${this.stateBackupBucket.bucketArn}/*`,
          ],
        }),
      ],
    });

    // Outputs for cross-stack references
    new cdk.CfnOutput(this, 'StateBackupBucketName', {
      value: this.stateBackupBucket.bucketName,
      description: `State backup bucket name - ${targetRegion}`,
      exportName: getExportName('StateBackupBucket-Name', targetRegion),
    });

    new cdk.CfnOutput(this, 'StateBackupBucketArn', {
      value: this.stateBackupBucket.bucketArn,
      description: `State backup bucket ARN - ${targetRegion}`,
      exportName: getExportName('StateBackupBucket-ARN', targetRegion),
    });

    new cdk.CfnOutput(this, 'BucketAccessPolicyArn', {
      value: bucketAccessPolicy.managedPolicyArn,
      description: `IAM policy ARN for bucket access - ${targetRegion}`,
      exportName: getExportName('BucketAccessPolicy-ARN', targetRegion),
    });

    // Output commands for manual backup/restore operations
    new cdk.CfnOutput(this, 'BackupCommand', {
      value: `aws s3 sync /etc/wireguard s3://${this.stateBackupBucket.bucketName}/wireguard-config/ --exclude "*.tmp" --delete --region ${targetRegion}`,
      description: 'Command to backup WireGuard configuration to S3',
    });

    new cdk.CfnOutput(this, 'RestoreCommand', {
      value: `aws s3 sync s3://${this.stateBackupBucket.bucketName}/wireguard-config/ /etc/wireguard --delete --region ${targetRegion}`,
      description: 'Command to restore WireGuard configuration from S3',
    });

    new cdk.CfnOutput(this, 'SecurityNote', {
      value: 'This bucket contains sensitive WireGuard private keys. Ensure proper IAM permissions and monitor access.',
      description: 'Important security reminder',
    });
  }
}