AWSTemplateFormatVersion: '2010-09-09'
Description: Template for the Creation of RDS based on Engine Choice
Metadata:
  'AWS::CloudFormation::Interface':
    ParameterGroups:
    - Label:
        default: 'RDS Parameters'
      Parameters:
      - DBSnapshotIdentifier
      - EngineVersion
      - DBAllocatedStorage
      - DBInstanceClass
      - DBName
      - DBBackupRetentionPeriod
      - DBMasterUsername
      - DBMasterUserPassword
      - DBMultiAZ
      - PreferredBackupWindow
      - PreferredMaintenanceWindow
      - EnableIAMDatabaseAuthentication

                      # Parameters CFN #
Parameters:
  Environment:
    Type: String
  Identifier:
    Type: String
  DBSnapshotName:
    Description: 'Optional name or Amazon Resource Name (ARN) of the DB snapshot from which you want to restore (leave blank to create an empty database).'
    Type: String
    Default: ''
  DBAllocatedStorage:
    Description: 'The allocated storage size, specified in GB (ignored when DBSnapshotIdentifier is set, value used from snapshot).'
    Type: Number
    Default: 5
    MinValue: 5
    MaxValue: 16384
  DBInstanceClass:
    Description: 'The instance type of database server.'
    Type: String
    Default: 'db.t2.micro'
  DBName:
    Description: The database name
    Type: String
    AllowedPattern: '[a-zA-Z][a-zA-Z0-9]*'
  DBBackupRetentionPeriod:
    Description: 'The number of days to keep snapshots of the database.'
    Type: Number
    MinValue: 0
    MaxValue: 35
    Default: 0
  DBMasterUsername:
    Description: The database admin account username
    Type: String
    Default: master
  DBMasterUserPassword:
    Default: root1234
    NoEcho: 'true'
    Description: The database admin account password
    Type: String
    MinLength: '8'
  DBMultiAZ:
    Description: 'Specifies if the database instance is deployed to multiple Availability Zones for HA.'
    Type: String
    Default: false
    AllowedValues: [true, false]
  DeleteAutomatedBackups:
    Description: 'Specifies if the database backup should be deleted.'
    Type: String
    Default: false
    AllowedValues: [true, false]    
  DeletionProtection:
    Description: 'Specifies if the database should be deleted.'
    Type: String
    Default: false
    AllowedValues: [true, false]  
  EnablePerformanceInsights:
    Description: 'Specifies if the Performance Insights should be enabled?'
    Type: String
    Default: false
    AllowedValues: [true, false]     
  PreferredBackupWindow:
    Description: 'The daily time range in UTC during which you want to create automated backups.'
    Type: String
    Default: '09:54-10:24'
  PreferredMaintenanceWindow:
    Description: The weekly time range (in UTC) during which system maintenance can occur.
    Type: String
    Default: 'sat:07:00-sat:07:30'
  PubliclyAccessible:
    Description: 'Specifies if the DB Public Access should be enabled?'
    Type: String
    Default: false
    AllowedValues: [true, false]  
  EnableIAMDatabaseAuthentication:
    Description: 'Enable mapping of AWS Identity and Access Management (IAM) accounts to database accounts (https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/UsingWithRDS.IAMDBAuth.html).'
    Type: String
    AllowedValues: ['true', 'false']
    Default: 'false'
  StorageType:
    Description: 'Storage Type of DB-Instance.'
    Type: String
    AllowedValues: ['standard', 'gp2', 'io1']
    Default: 'gp2'
  UseDefaultProcessorFeatures:
    Description: 'Indicates whether the DB instance class of the DB instance uses its default processor features.'
    Type: String
    Default: false
    AllowedValues: [true, false]  
  VPCId: 
    Description: Create security group in this respective VPC
    Type: String
  privatesubnet01:
    Description: The Amazon RDS Subnet-1.  
    Type: String 
  privatesubnet02:
    Description: The Amazon RDS Subnet-2.  
    Type: String
  DBEncryptionKmsAlias:
    Description: The alias for Key Management Service encryption key alias
    Type: String
    Default: ''
  DatabaseEngine:
    Description: 'Database Engine version.'
    Type: String
    AllowedValues: [postgres, mysql, aurora-mysql, aurora]
{%if 'sgGroup' in rds_data %}
{% for key in rds_data['sgGroup'] %}
  {{ key }}:
    Description: 'Database Security Group.'
    Type: String
{%endfor%}
{% endif %}
  InstanceIdentifier:
    Type: String      

                # Conditions CFN #
Conditions:
  useDBEncryptionKmsAlias: !Not
    - !Equals
      - !Ref 'DBEncryptionKmsAlias'
      - ''
  useDBSnapshot: !Not
    - !Equals
      - !Ref 'DBSnapshotName'
      - ''


                # Resources CFN #
Resources:


  DBSubnetGroup:
    Type: AWS::RDS::DBSubnetGroup
    Properties:
      DBSubnetGroupDescription: rds private subnet 
      SubnetIds:
        - !Ref privatesubnet01
        - !Ref privatesubnet02


  DBInstance:
    DeletionPolicy: Snapshot # default
    UpdateReplacePolicy: Snapshot
    Type: 'AWS::RDS::DBInstance'
    Properties:
      AllocatedStorage: !Ref DBAllocatedStorage
      DBInstanceIdentifier: !Ref InstanceIdentifier
      AllowMajorVersionUpgrade: false
      AutoMinorVersionUpgrade: true
      BackupRetentionPeriod: !Ref DBBackupRetentionPeriod
      CopyTagsToSnapshot: true
      EnablePerformanceInsights: !Ref EnablePerformanceInsights  
      DBInstanceClass: !Ref DBInstanceClass
      DBName: !Ref DBName
      DBSnapshotIdentifier: !If
        - useDBSnapshot
        - !Ref 'DBSnapshotName'
        - !Ref 'AWS::NoValue'      
      DBSubnetGroupName: !Ref DBSubnetGroup
      DeleteAutomatedBackups: !Ref DeleteAutomatedBackups
      DeletionProtection: !Ref DeletionProtection
      EnableIAMDatabaseAuthentication: !Ref EnableIAMDatabaseAuthentication
      Engine: !Ref DatabaseEngine
      MasterUsername: !Ref DBMasterUsername
      MasterUserPassword: !Ref DBMasterUserPassword
      MultiAZ: !Ref DBMultiAZ
      PreferredBackupWindow: !Ref PreferredBackupWindow
      PreferredMaintenanceWindow: !Ref PreferredMaintenanceWindow
      StorageType: !Ref StorageType
      PubliclyAccessible: !Ref PubliclyAccessible
      StorageEncrypted: !If
        - useDBEncryptionKmsAlias
        - 'true'
        - 'false'
      KmsKeyId: !If
        - useDBEncryptionKmsAlias
        - !Ref 'DBEncryptionKmsAlias'
        - !Ref 'AWS::NoValue'      
      Tags:
        - Key: Name
          Value: !Sub '${Identifier}-${Environment}-RDS'   
      UseDefaultProcessorFeatures: !Ref UseDefaultProcessorFeatures
      VPCSecurityGroups:
{%if 'sgGroup' in rds_data %}
{% for key in rds_data['sgGroup'] %}
      - !Ref {{ key }}
{%endfor%}
{% endif %}


Outputs:
  EndpointandPort:
    Description: Endpoint and port of the database
    Value: !Join ['', [!Ref 'DatabaseEngine', '://', !GetAtt [DBInstance, Endpoint.Address], ':', !GetAtt [DBInstance, Endpoint.Port], /, !Ref 'DBName']]