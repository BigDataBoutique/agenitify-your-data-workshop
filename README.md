# agenitify-your-data-workshop+rekognition+postgres

## Pre-requisites
1. Follow the kb workshop guide to create kb_agent

## Provision Rekognition infrastructure
In this step we will provision an AWS S3 bucket to store images + IAM role that allows to use AWS Rekognition service + bucket access
Our agent will be able to assume this role using trust policy
**note** use the same AWS Region as used in the Workshop account 

### Option 1 - Provision Rekognition infrastructure via terraform

1. Edit terraform/terraform.tfvars
 - `runtime_account_id` - this is the AWS account of the workshop
 - `bucket_name` - S3 bucket name that will be created under *your own* AWS account
 - `aws_region` the region that hosts the kb_agent
 - **note**: Terraform will create a role named `RekognitionAccessRole` under your AWS account, in case you wish to change it, override `rekognition_role_name`
2. Apply the infrastructure. This is normally done with **Terraform**:
     ```
     cd terraform
     terraform init
     terraform apply
    ```
   - note the printed `rekognition_role_arn` output — you'll set it as `REKOGNITION_ROLE_ARN` in the agent runtime.
   
### Option 2 - Provision Rekognition infrastructure via provision shell script   

1. edit the `CONFIGURATION` block at the top of the `provision.sh` script (`bucket_name`, `runtime_account_id`, `aws_region`, …)
2. Run it:
     ```shell
     ./provision.sh --profile <your-aws-profile>
     ```
     Options: `--profile <aws_profile>` selects the AWS CLI profile (otherwise the default credentials / `AWS_PROFILE` are used); `--destroy` tears everything down again. Any variable can also be passed via the environment instead of editing the script, e.g. `bucket_name=my-bucket runtime_account_id=123... ./provision.sh`.
   - note the printed `rekognition_role_arn` output — you'll set it as `REKOGNITION_ROLE_ARN` in the agent runtime.

### Upload images and create postgres  
1. Upload images you want to read the text from to the bucket created
2. Add a policy to the AgentCoreRuntimeRole role in the agent environment:
{
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::accountid:role/RekognitionAccessRole"
    }
  ]
} 
3. Create a PostgreSQL database on Aiven, create the tables from schemas.sql and populate them using seed.sql

## Code deploy
1. Copy .env-example to .env file and fill it with the following details:
 - `REKOGNITION_BUCKET` - The S3 bucket name that was provisioned, the agent will translate images that would be stored on this bucket
 - `REKOGNITION_ROLE_ARN` - The role that was provisioned
 - `POSTGRES_USER` - Username to interact with Postgres
 - `POSTGRES_PASSWORD` - Password to interact with Postgres
 - `POSTGRES_JDBC_URL` - The JDBC URL to interact with Postgres
2. Save the knowledge base id you're using, you can find it inside 2-kb-agent/kb_agent_tools.py
3. **Important** backup the entire `2-kb-agent` directory by copy all the directory content into another directory, e.g `2-kb-agent-orig`
4. Use the files under `agent` local directory, to override files that inside `2-kb-agent`, override Python files and requirements.txt
Place query_examples.md and schema.sql under `2-kb-agent` directory
9. Deploy: ```uv run --env-file .env kb_agent_deploy.py```
10. Test: make sure kb_agent_test.py uses the arn created during deploy, then ```uv run ./kb_agent_test.py```
11. With any issue in testing, look at Bedrock Agentcore trace in Cloudwatch, and track down the tool that had the issue
