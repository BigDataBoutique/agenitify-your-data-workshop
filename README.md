# agenitify-your-data-workshop+rekognition+postgres

## Provision infrastructure
1. Follow the kb workshop guide to create kb_agent
2. Use terraform to create the assets for rekognition in *your own* cloud environment. 
It should be in the same region as the agent environment. You can fill in the parameters in the tfvars file, 
runtime account id is the account for the agent environment.
3. Edit terraform/terraform.tfvars
 - `runtime_account_id` - this is the AWS account of the workshop
 - `bucket_name` - S3 bucket name that will be created under *your own* AWS account
 - `aws_region` the region that hosts the agent from step 2
 - **note**: Terraform will create a role named `RekognitionAccessRole` under your AWS account, in case you wish to change it, override `rekognition_role_name` 
4. Upload images you want to read the text from to the bucket created
5. Add a policy to the AgentCoreRuntimeRole role in the agent environment:
{
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::accountid:role/RekognitionAccessRole"
    }
  ]
} 
6. Create a PostgreSQL database on Aiven, create the tables from schemas.sql and populate them using seed.sql

## Code deploy
1. Copy .env-example to .env file and fill it with the following details:
 - `REKOGNITION_BUCKET` - The S3 bucket name that was provisioned, the agent will translate images that would be stored on this bucket
 - `REKOGNITION_ROLE_ARN` - The role that was provisioned
 - `POSTGRES_USER` - Username to interact with Postgres
 - `POSTGRES_PASSWORD` - Password to interact with Postgres
 - `POSTGRES_JDBC_URL` - The JDBC URL to interact with Postgres
2. Save the knowledge base id you're using, you can find it inside 2-kb-agent/kb_agent_tools.py
3. **Important** backup the entire `2-kb-agent` directory by copy all the directory content into another directory, e.g `2-kb-agent-orig`
4. Use the files under `agent` local directory, to override files that inside `2-kb-agent`, override Python files and requirement.txt
Place query_examples.md and schema.sql under `2-kb-agent` directory
9. Deploy: ```uv run --env-file .env kb_agent_deploy.py```
10. Test: ```uv run ./kb_agent_test.py```
11. With any issue in testing, look at Bedrock Agentcore trace in Cloudwatch, and track down the tool that had the issue
