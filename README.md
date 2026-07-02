# agenitify-your-data-workshop+rekognition+postgres
1. Follow the kb workshop guide
2. Use terraform to create the assets for rekognition in your own cloud environment. 
It should be in the same region as the agent environment. You can fill in the parameters in the tfvars file, 
runtime account id is the account for the agent environment.
3. Upload images you want to read the text from to the bucket created
4. Add a policy to the AgentCoreRuntimeRole role in the agent environment:
{
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::accountid:role/RekognitionAccessRole"
    }
  ]
}
5. copy .env-example to .env file and fill it with the bucket name and the arn for the RekognitionAccessRole role
6. Create a postres database on Aiven, create the tables from schemas.sql and populate them using seed.sql
7. Fill in the .env file with the details for postgres
8. Save the knowledge base id you're using, then override the py files, requirement.txt, query_examples.md and schema.sql 
in the agent folder on the code server, then replace the knowledge base id
9. Deploy:
uv run --env-file .env kb_agent_deploy.py
10. Test.  
uv run ./kb_agent_test.py
11. With any issue in testing, look at Bedrock Agentcore trace in Cloudwatch, and track down the tool that had the issue
