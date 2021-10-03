AWSTemplateFormatVersion: 2010-09-09
Description: |
  "Template for the creation of new vpc,subnets,igw,nat,route table, routes etc"
Parameters:
  Environment:
    Type: String
  Identifier:
    Type: String
  VpcCidrBlock:
    Description: Cidr Block Range for VPC
    Type: String
    Default: 10.0.0.0/16
Resources:
  MyVpc:
    Type: 'AWS::EC2::VPC'
    Properties:
      CidrBlock: !Ref VpcCidrBlock
      EnableDnsHostnames: true
      EnableDnsSupport: true
      Tags:
        - Key: Name
          Value: !Sub '${Identifier}-${Environment}-VPC'
{% if 'Subnets' in subnet_data %}
{% for i in range(subnet_data['Subnets'][0]['Public'] | length) %}
  PublicSubnet{{i+1}}:
    Type: 'AWS::EC2::Subnet'
    Properties:
      VpcId: !Ref MyVpc
      MapPublicIpOnLaunch: Yes
      CidrBlock: {{subnet_data['Subnets'][0]['Public'][i]['CidrBlock']}}
      AvailabilityZone: {{subnet_data['Subnets'][0]['Public'][i]['AvailabilityZone']}}
      Tags:
        - Key: Name
          Value: !Sub '${Identifier}-${Environment}-PublicSubnet{{i+1}}'

{% endfor %}

{%endif%}
{% if 'Subnets' in subnet_data %}
{% for i in range(subnet_data['Subnets'][0]['Private'] | length) %}
  PrivateSubnet{{i+1}}:
    Type: 'AWS::EC2::Subnet'
    Properties:
      VpcId: !Ref MyVpc
      MapPublicIpOnLaunch: No
      CidrBlock: {{subnet_data['Subnets'][0]['Private'][i]['CidrBlock']}}
      AvailabilityZone: {{subnet_data['Subnets'][0]['Private'][i]['AvailabilityZone']}}
      Tags:
        - Key: Name
          Value: !Sub '${Identifier}-${Environment}-PrivateSubnet{{i+1}}'

{% endfor %}

{%endif%}
  MyIGW:
    Type: 'AWS::EC2::InternetGateway'
    Properties:
      Tags:
        - Key: Name
          Value: !Sub '${AWS::StackName}'
  MyVpcIGWAttachment:
    Type: 'AWS::EC2::VPCGatewayAttachment'
    Properties:
      InternetGatewayId: !Ref MyIGW
      VpcId: !Ref MyVpc
  MyNATEIP:
    Type: 'AWS::EC2::EIP'
    Properties:
      Domain: vpc
      Tags:
        - Key: Name
          Value: !Sub '${Identifier}-${Environment}-NATIp'
  MyNatGat:
    Type: 'AWS::EC2::NatGateway'
    Properties:
      SubnetId: !Ref PublicSubnet1
      AllocationId: !GetAtt MyNATEIP.AllocationId
      Tags:
        - Key: Name
          Value: !Sub '${Identifier}-${Environment}-NatGateway'
  MyPublicRouteTable:
    Type: 'AWS::EC2::RouteTable'
    Properties:
      VpcId: !Ref MyVpc
      Tags:
        - Key: Name
          Value: !Sub '${Identifier}-${Environment}-PublicRouteTable'
  MyPrivateRouteTable:
    Type: 'AWS::EC2::RouteTable'
    Properties:
      VpcId: !Ref MyVpc
      Tags:
        - Key: Name
          Value: !Sub '${Identifier}-${Environment}-PrivateRouteTable'
  WWWRouteToIGW:
    Type: 'AWS::EC2::Route'
    Properties:
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref MyIGW
      RouteTableId: !Ref MyPublicRouteTable
  PriSubnetToNat:
    Type: 'AWS::EC2::Route'
    Properties:
      DestinationCidrBlock: 0.0.0.0/0
      NatGatewayId: !Ref MyNatGat
      RouteTableId: !Ref MyPrivateRouteTable

{% for i in range(subnet_data['Subnets'][0]['Public'] | length) %}
  PublicSubnet{{i+1}}Asso:
    Type: 'AWS::EC2::SubnetRouteTableAssociation'
    Properties:
      RouteTableId: !Ref MyPublicRouteTable
      SubnetId: !Ref PublicSubnet{{i+1}}
{% endfor %}

{% for i in range(subnet_data['Subnets'][0]['Private'] | length) %}
  PrivateSubnet{{i+1}}Asso:
    Type: 'AWS::EC2::SubnetRouteTableAssociation'
    Properties:
      RouteTableId: !Ref MyPrivateRouteTable
      SubnetId: !Ref PrivateSubnet{{i+1}}
{% endfor %}

{% for i in range(sg_data['SecurityGroup'] | length) %}
{% for j in range(sg_data['SecurityGroup'][i]['inbound'] | length) %}
  {{ sg_data['SecurityGroup'][i]['Name'] }}Ingress0{{j+1}}:
    Type: 'AWS::EC2::SecurityGroupIngress'
    Properties:
{% if 'CidrIp' in sg_data['SecurityGroup'][i]['inbound'][j]  %}
      CidrIp: {{ sg_data['SecurityGroup'][i]['inbound'][j]['CidrIp']}}
{% else %}
      SourceSecurityGroupId: !Ref {{ sg_data['SecurityGroup'][i]['inbound'][j]['SourceSecurityGroupId']}}
{% endif %}
      GroupId: !Ref {{ sg_data['SecurityGroup'][i]['Name'] }}
      IpProtocol: {{ sg_data['SecurityGroup'][i]['inbound'][j]['IpProtocol'] }}
      FromPort: {{ sg_data['SecurityGroup'][i]['inbound'][j]['FromPort'] }}
      ToPort: {{ sg_data['SecurityGroup'][i]['inbound'][j]['ToPort'] }}
{%endfor%}
{%endfor%}

{% for i in range(sg_data['SecurityGroup'] | length) %}
{% for j in range(sg_data['SecurityGroup'][i]['outbound'] | length) %}
  {{ sg_data['SecurityGroup'][i]['Name'] }}Egress0{{j+1}}:
    Type: 'AWS::EC2::SecurityGroupEgress'
    Properties:
      CidrIp: {{ sg_data['SecurityGroup'][i]['outbound'][j]['CidrIp']}}
      GroupId: !Ref {{ sg_data['SecurityGroup'][i]['Name'] }}
      IpProtocol: {{ sg_data['SecurityGroup'][i]['outbound'][j]['IpProtocol'] }}
      FromPort: {{ sg_data['SecurityGroup'][i]['outbound'][j]['FromPort'] }}
      ToPort: {{ sg_data['SecurityGroup'][i]['outbound'][j]['ToPort'] }}
{%endfor%}
{%endfor%}



{% if 'SecurityGroup' in sg_data %}
{% for i in range(sg_data['SecurityGroup'] | length) %}
  {{ sg_data['SecurityGroup'][i]['Name'] }}:
    Type: 'AWS::EC2::SecurityGroup'
    Properties:
      GroupDescription: '{{ sg_data['SecurityGroup'][i]['GroupDescription'] }}'
      GroupName: {{ sg_data['SecurityGroup'][i]['GroupName'] }}
      VpcId: !Ref MyVpc
      Tags:
        - Key: Name
          Value: !Sub '${Identifier}-${Environment}-{{ sg_data['SecurityGroup'][i]['Name'] }}'
{%endfor%}
{%endif %}
          
Outputs:
  VPC:
    Description: VPC ID
    Value: !Ref MyVpc
{% for i in range(subnet_data['Subnets'][0]['Public'] | length) %}
  PublicSubnet{{i+1}}:
    Value: !Ref PublicSubnet{{i+1}}
{%endfor%}
{% for i in range(subnet_data['Subnets'][0]['Private'] | length) %}
  PrivateSubnet{{i+1}}:
    Value: !Ref PrivateSubnet{{i+1}}
{%endfor%}
{% for i in range(sg_data['SecurityGroup'] | length) %}
  {{ sg_data['SecurityGroup'][i]['Name'] }}:
    Description: '{{ sg_data['SecurityGroup'][i]['GroupDescription'] }}'
    Value: !Ref {{ sg_data['SecurityGroup'][i]['Name'] }}
{%endfor%}