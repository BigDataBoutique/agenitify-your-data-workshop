# agenitify-your-data-workshop+rekognition+postgres
In this workshop we are going to add two new capabilities to the KB agent (part 2):
 - Text to SQL - the agent will create SQL statements and execute queries from free text
   - We provided demo data, but you may use your own demo data
 - Text recognition - the agent will extract text from images
   - We created a POC bucket and user that can access AWS Rekognition for the workshop
     - We uploaded a sample image to the bucket under the following key ```s3://<BUCKET_NAME>/example_image/example_image.png ```

## Pre-requisites
1. Follow the kb workshop guide to create kb_agent


### Postgres creation for `text to SQL` tool
1. Bring your own Postgres with demo data, or create a PostgreSQL database. 
You can use RDS or Aiven, you can create the tables from schemas.sql and populate them using seed.sql


### Optional Steps for image to text
For text to SQL tool, we already created an example bucket and image
For those who wish to wirk with custom image, do upload an image via AWS Cli to a dedicated key (create a named directory)

#### Upload images for `image to text` tool
In order to be able to a custom upload images via CLI
Configure the following AWS profile via aws configure command (we will provide AWS access key ID and access secret key):
```shell
aws configure --profile aws-workshop  --region "eu-west-2"
```
The bucket already has an example image under this key: ```example_image/example_image.png```
Upload image using the below command
```aws s3 cp --profile aws-workshop <PATH_TO_LOCAL_IMAGE>  s3://<BUCKET_NAME>/<YOUR_DEDICATED_DIRECTORY>/<IMAGE_FILE>```

## Code deploy
1. Copy .env-example to .env file and fill it with the following details:
 - `POSTGRES_USER` - Username to interact with Postgres
 - `POSTGRES_PASSWORD` - Password to interact with Postgres
 - `POSTGRES_JDBC_URL` - The JDBC URL to interact with Postgres
 - `REKOGNITION_BUCKET` - The S3 bucket name that we will provide
 - `REKOGNITION_ACCESS_KEY_ID` - The access key of the user who's able to access rekognition 
 - `REKOGNITION_ACCESS_SECRET` - The access secret of the user who's able to access rekognition 
 - `REKOGNITION_BUCKET_IMAGE_DIR` - what is the relevant directory that contains the image, the default path points to our example directory

2. Save the knowledge base id you're using, you can find it inside 2-kb-agent/kb_agent_tools.py
3. **Important** backup the entire `2-kb-agent` directory by copy all the directory content into another directory, e.g `2-kb-agent-orig`
4. Use the files under `agent` local directory, to override files that inside `2-kb-agent`, override Python files and requirements.txt
Place query_examples.md and schema.sql under `2-kb-agent` directory
5. Deploy: ```uv run --env-file .env kb_agent_deploy.py```
6. Test: make sure kb_agent_test.py uses the arn created during deploy and it has the right prompt, then ```uv run ./kb_agent_test.py```
7. With any issue in testing, look at Bedrock Agentcore trace in Cloudwatch, and track down the tool that had the issue
