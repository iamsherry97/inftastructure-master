#!/usr/bin/python
import json, os, boto3, sys, time, collections, jinja2
from jinja2 import Environment, FileSystemLoader
from pathlib import Path

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
environment = ""
app = ""

def main():
    """CLI used to deploy to AWS environments."""
    while True:
        global environment
        global app

        apps = get_apps()

        for i in range(len(apps)):
            print(str(i + 1) + ". " + apps[i])

        selected_input_index = input("\nPlease select the App: ")
        app = apps[int(selected_input_index) - 1]
        print("You have selected: " + app)

        print_separator()

        environments = get_environments()

        for i in range(len(environments)):
            print(str(i + 1) + ". " + environments[i])

        selected_input_index = input("\nPlease select the environment: ")
        environment = environments[int(selected_input_index) - 1]
        print("You have selected: " + environment)

        print_separator()

        conf = get_conf()
        environment = conf['Environment']
        perform_jinja_templating(environment, app, conf)
        templates = get_available_templates(conf)
        print("Uploading templates, Please wait ...")
        upload_files_to_bucket(conf['BucketName'])

        print("\n")
        print("1. Select all the templates")
        print("2. Select the single template yourself")
        selected_input_index = input("\nHow do you want to proceed: ")

        print_separator()

        if selected_input_index == "1":

            print("1. Do you want to update/create the stack")
            print("2. Do you want to delete the stack")
            selected_input_index = input("\nHow do you want to proceed: ")

            if selected_input_index == "1":
                deploy_stack_priority_wise(conf)
            else:
                delete_stack_priority_wise(conf)
        else:
            for i in range(len(templates)):
                print("%s. %s" % (str(i + 1), templates[i]))

            selected_input_index = input("\nPlease select the template: ")
            template = templates[int(selected_input_index) - 1]

            print_separator()

            print("1. Do you want to update/create the stack")
            print("2. Do you want to delete the stack")
            selected_input_index = input("\nHow do you want to proceed: ")

            if str(selected_input_index) == "1":
                deploy(template)
            else:
                delete_stack_by_checking_dependency(template, conf)

        print_separator()

        print("1. Please press '1' to continue")
        print("2. Press another key to exit the cli")
        selected_input_index = input("\nHow do you want to proceed: ")

        if str(selected_input_index) != "1":
            print("Bye!")
            break
        else:
            print_separator()


def delete_stack_by_checking_dependency(template, conf):
    region = conf["Region_ID"]
    identifier = conf['Identifier']
    cloudformation_client = boto3.client('cloudformation', region_name=region)
    is_higher_priority_stack_exists = False

    selected_stack_priority = int(conf[template]['_Priority'])
    stacks = set_stacks_priority(conf)
    stacks_list = sorted(stacks.items(), key=lambda kv: kv[1], reverse = True)

    for key in stacks_list:
        stack = "%s-%s-%s" % (identifier, environment, key[0])
        if selected_stack_priority < key[1] and does_stack_exist(stack, cloudformation_client) != None:
            is_higher_priority_stack_exists = True
            print("\nPlease delete the the higher priority({priority}) {stack}'s stack first.".format(stack=key[0], priority=key[1]))
            break

    if not is_higher_priority_stack_exists:
        delete(template)



def delete(template):
    """ destroy the cloudformation templates to an environment"""
    conf = get_conf()
    region = conf["Region_ID"]
    identifier = conf['Identifier']
    cloudformation_client = boto3.client('cloudformation', region_name=region)

    print_separator()

    print("Deleting %s-%s-%s" % (identifier, environment, template))
    stack = "%s-%s-%s" % (identifier, environment, template)
    is_stack_exists = does_stack_exist(stack, cloudformation_client)

    print("stack exist")
    if is_stack_exists != None:
        cloudformation_client.delete_stack(StackName=stack)
        check_status(stack, cloudformation_client)


def deploy(template):
    conf = get_conf()
    region = conf["Region_ID"]
    bucket_uri = conf["Bucket_URI"]
    identifier = conf["Identifier"]
    cloudformation_client = boto3.client('cloudformation', region_name=region)

    stack = "%s-%s-%s" % (identifier, environment, template)
    parameters = get_parameters(conf, template)
    template_path = conf[template]["_Path"]
    template_url = bucket_uri + environment + template_path

    stack_id = does_stack_exist(stack, cloudformation_client)
    print_separator()
    print("Selected Stack: " + stack)

    if stack_id is None:
        print("\nCreating stack")
        stack_id = cloudformation_client.create_stack(StackName=stack, DisableRollback=True, TemplateURL=template_url,
                                                      Parameters=parameters,
                                                      Capabilities=["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM"])
        check_status(stack, cloudformation_client)
    else:
        try:
            print("\nUpdating stack")
            stack_id = cloudformation_client.update_stack(StackName=stack, TemplateURL=template_url,
                                                          Parameters=parameters,
                                                          Capabilities=["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM"])
            check_status(stack, cloudformation_client)
        except Exception as e:
            print(e)
            print("\nNo changes to the current stack ")


def get_secret_from_ssm(key):
    conf = get_conf()
    region = conf["Region_ID"]
    parameter_store = boto3.client('ssm', region_name=region)
    parameter = parameter_store.get_parameter(
        Name=key,
        WithDecryption=True
    )
    return parameter['Parameter']['Value']


def get_conf():
    conf_path = 'apps/%s/conf/%s.json' % (app, environment)
    # -- Confirm parameters file exists
    if os.path.isfile(conf_path):
        conf_data = open(conf_path).read()
    else:
        print('ERROR - Parameter file %s does not exist in app %s' % (conf_path, app))
        sys.exit(3)
    print(f"loading {conf_path}")
    return json.loads(conf_data)


def get_available_templates(conf):
    available_templates = []
    for parameter in conf.keys():
        if isinstance(conf[parameter], dict):
            for key in conf[parameter].keys():
                if key == "_Path":
                    available_templates.append(parameter)
    return available_templates


def get_parameters(conf, template):
    stack_parameters = []
    try:
        conf_template = conf[template]
    except KeyError as e:
        print(conf)
        raise e
    for parameter in conf_template.keys():
        if "_Secret_" in parameter:
            ssm_key = conf_template[parameter]
            real_parameter_name = parameter.split("_Secret_")[1]
            value = get_secret_from_ssm(ssm_key)
            stack_parameters.append({"ParameterKey": real_parameter_name, "ParameterValue": value})
        elif parameter.startswith('_'):
            continue
        else:
            value = conf_template[parameter]
            if value.startswith('{'):
                value = value.replace('{', '').replace('}', '')
                value = conf[value]
            stack_parameters.append({"ParameterKey": parameter, "ParameterValue": value})

    stack_parameters.append({"ParameterKey": "Environment", "ParameterValue": conf['Environment']})
    stack_parameters.append({"ParameterKey": "Identifier", "ParameterValue": conf['Identifier']})

    return stack_parameters


def does_stack_exist(stack_name, cloudformation_client):
    stack_list = cloudformation_client.describe_stacks()["Stacks"]
    does_stack_exist = None
    for stack in stack_list:
        if stack_name == stack["StackName"]:
            does_stack_exist = stack["StackName"]
    return does_stack_exist


def check_status(stack_name, cloudformation_client):
    stacks = cloudformation_client.describe_stacks(StackName=stack_name)["Stacks"]
    stack = stacks[0]
    current_status = stack["StackStatus"]
    print("Current status of stack " + stack["StackName"] + ": " + current_status)
    error_count = 0
    for loop in range(1, 9999):
        if "IN_PROGRESS" in current_status:
            print("Waiting for status update(" + str(loop) + ")..." + current_status)
            time.sleep(5)  # pause 1 seconds

            try:
                stacks = cloudformation_client.describe_stacks(StackName=stack_name)["Stacks"]
                error_count = 0
            except:
                error_count += 1
                print(" ")
                print("Error getting status for Stack " + stack["StackName"] + "!")
                print("Retry status check (" + str(error_count) + ")...")
                if error_count > 4:
                    current_status = "STACK_DELETED"
                    break

            stack = stacks[0]

            if stack["StackStatus"] != current_status:
                current_status = stack["StackStatus"]
                print(" ")
                print("Updated status of stack " + stack["StackName"] + ": " + current_status)
        else:
            break

    return current_status


def set_stacks_priority(conf):
    priority = {}
    for parameter in conf.keys():
        if isinstance(conf[parameter], dict):
            for key in conf[parameter].keys():
                if key == "_Path":
                    priority[parameter] = conf[parameter].get('_Priority')
    return priority

def print_separator():
    print("\n")
    for i in range(2):
        print("###############################")
    print("\n")

def get_apps():
    apps = []
    for appname in os.listdir("apps/"):
        apps.append(appname)
    return apps

def get_environments():
    environments = []
    for filename in os.listdir("apps/" + app + "/conf/"):
            environments.append(os.path.splitext(filename)[0])
    return environments

def deploy_stack_priority_wise(conf):
    stacks = set_stacks_priority(conf)
    stacks_list = sorted(stacks.items(), key=lambda kv: kv[1])
    sorted_stacks_list = collections.OrderedDict(stacks_list)
    for template in sorted_stacks_list:
        deploy(template)

def delete_stack_priority_wise(conf):
    stacks = set_stacks_priority(conf)
    stacks_list = sorted(stacks.items(), key=lambda kv: kv[1], reverse = True)
    sorted_stacks_list = collections.OrderedDict(stacks_list)
    for template in sorted_stacks_list:
        delete(template)

def upload_files_to_bucket(bucket_name):
    os.system("aws s3 cp apps/%s/ s3://%s%s/ --recursive " % (app, bucket_name, environment))
    os.system("aws s3 cp common s3://%s%s/common/ --recursive " % (bucket_name, environment))

def perform_jinja_templating(environment, app, conf):
    jinja_template_path = "apps/{app_name}/templates/task_definitions/".format(app_name=app)
    jinja_template_file_name = "{app_name}.tpl".format(app_name=app)
    complete_jinja_template_path = jinja_template_path + jinja_template_file_name


    if 'Service' in conf and os.path.exists(complete_jinja_template_path):
        data = {}

        if '_task_definition_environment' in conf['Service']:
            data['task_definition_environment'] = conf['Service']['_task_definition_environment']

        if '_task_definition_secret' in conf['Service']:
            data['task_definition_secret'] = conf['Service']['_task_definition_secret']

        j2_env = Environment(loader=FileSystemLoader(THIS_DIR),
                         trim_blocks=True)

        rendered_text = j2_env.get_template(complete_jinja_template_path).render(
                            data = data
                        )
        yaml_file_name = Path(jinja_template_file_name).stem + ".yml"
        with open(jinja_template_path + yaml_file_name, "w") as yaml_file:
            yaml_file.write(rendered_text)


if __name__ == '__main__':
    main()
