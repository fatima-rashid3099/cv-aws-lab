# Host Your CV on AWS

Roll number: **23L-3099**
Region: **ap-southeast-2 (Sydney)**

| Path | Address |
|---|---|
| EC2 | http://54.253.18.104/ |
| Lambda | https://plizupvtyjd4ezbbfdndi7omsy0sxycp.lambda-url.ap-southeast-2.on.aws/ |

To run the evidence script (use `bash` because the file may not be marked executable):

```
bash collect-evidence.sh cv-23l-3099 http://54.253.18.104 https://plizupvtyjd4ezbbfdndi7omsy0sxycp.lambda-url.ap-southeast-2.on.aws
```

## 1. Diagram

```
                      +-----------------------------------------+
                      |   S3 bucket: cv-23l-3099 (PRIVATE)      |
                      |   site/index.html  site/style.css       |
                      |   site/cv.pdf                           |
                      +--------------^------------------^-------+
                                     |                  |
              GetObject + ListBucket |                  | GetObject
                  (EC2 role)         |                  | (Lambda role)
                                     |                  |
   Path A                    +-------+------+    +------+---------+       Path B
 Visitor --HTTP 80-->        | EC2 t3.micro |    | Lambda function |   <--HTTPS-- Visitor
                             | Apache + sync|    | Function URL    |
                             | timer (2 min)|    | (auth NONE)     |
                             +--------------+    +-----------------+

 Visitor --> S3 object URL directly --> 403 Access Denied
```

**Path A (EC2):** A visitor's browser connects to the instance's public IP on port 80, where Apache serves the files that a systemd timer copies from the `site/` prefix of the bucket every 2 minutes, using the EC2 role. The sync script replaces the placeholder with `EC2` and the instance ID.

**Path B (Lambda):** A visitor's browser calls the public HTTPS function URL, which runs the function. The function reads the requested file from the bucket with the Lambda role, replaces the placeholder with `Lambda` and the function name, and returns it.

## 2. Access denied output (section 4)

Run from a shell on the instance, which uses the EC2 role:

```
[ec2-user@ip-172-31-35-21 ~]$ aws s3 rm s3://cv-23l-3099/site/index.html --region ap-southeast-2
delete failed: s3://cv-23l-3099/site/index.html An error occurred (AccessDenied) when calling the DeleteObject operation: User: arn:aws:sts::473247068828:assumed-role/cv-ec2-role-23l-3099/i-0f9fa5ce467bd1461 is not authorized to perform: s3:DeleteObject on resource: "arn:aws:s3:::cv-23l-3099/site/index.html" because no identity-based policy allows the s3:DeleteObject action
[ec2-user@ip-172-31-35-21 ~]$ aws s3 cp /etc/hostname s3://cv-23l-3099/site/index.html --region ap-southeast-2
upload failed: ../../etc/hostname to s3://cv-23l-3099/site/index.html An error occurred (AccessDenied) when calling the PutObject operation: User: arn:aws:sts::473247068828:assumed-role/cv-ec2-role-23l-3099/i-0f9fa5ce467bd1461 is not authorized to perform: s3:PutObject on resource: "arn:aws:s3:::cv-23l-3099/site/index.html" because no identity-based policy allows the s3:PutObject action
```

## 3. Last 10 lines of /var/log/cv-sync.log

```
2026-10-25T16:35:47Z sync OK instance=i-0f9fa5ce467bd1461
2026-10-25T16:37:47Z sync OK instance=i-0f9fa5ce467bd1461
2026-10-25T16:39:47Z sync OK instance=i-0f9fa5ce467bd1461
2026-10-25T16:41:47Z sync OK instance=i-0f9fa5ce467bd1461
2026-10-25T16:43:47Z sync OK instance=i-0f9fa5ce467bd1461
2026-10-25T16:45:47Z sync OK instance=i-0f9fa5ce467bd1461
2026-10-25T16:47:47Z sync OK instance=i-0f9fa5ce467bd1461
2026-10-25T16:49:48Z sync OK instance=i-0f9fa5ce467bd1461
2026-10-25T16:51:48Z sync OK instance=i-0f9fa5ce467bd1461
2026-10-25T16:53:48Z sync OK instance=i-0f9fa5ce467bd1461
```

## 4. Written answers

**1. Why do the instance and the function use roles instead of access keys? What could go wrong if the keys were in the user data?**

A role gives the instance or function temporary credentials that AWS creates and rotates automatically, so there is no secret for me to store or lose. Access keys are long-lived, and keys in the user data could be read by anyone who can view the instance's settings, and could easily be copied into my public repository. Anyone who found them could use them from anywhere, with the key's full permissions, until I noticed and deactivated them. Role credentials expire after a few hours, so a leak does far less damage.

**2. Someone pastes the S3 address of index.html into a browser. What do they see, and which setting causes that?**

They see an XML page saying Access Denied (HTTP 403). This is caused by the Block Public Access settings, which are all on for the bucket, together with the fact that there is no public bucket policy or ACL. A browser request carries no AWS credentials, so S3 refuses it. Only my two roles are allowed to read the objects.

**3. Explain in your own words the permission on the function URL that lets anyone call it. Why is that acceptable for the function but not for the bucket?**

With authentication type NONE, the console adds a resource-based policy on the function that allows any principal (`*`) to perform `lambda:InvokeFunctionUrl`, so a visitor does not need an AWS identity to call the URL. This is acceptable because the function's own code decides what is returned: it only serves three fixed paths, and its role can only read `site/`. Making the bucket public would instead let anyone read, and possibly list, everything in it, including anything I add later, with no code in between to control it. The public door is on the program that I wrote, not on the data store behind it.

**4. Compare the two paths. What do you pay for when nobody visits the site? What happens if the traffic grows a hundred times?**

The EC2 path costs money even with no visitors, because the instance runs and bills for every hour, plus its disk and public IPv4 address. The Lambda path costs almost nothing when idle, because I pay only per request and for the milliseconds of running time. With a hundred times the traffic, one small instance could become slow or fail unless I add bigger servers or a load balancer myself. Lambda scales out automatically, and my bill simply rises with the number of requests.

**5. You delete the EC2 instance. What do you lose and what do you still have?**

I lose the running server, its disk and the copy of the site on it, the sync log, and the EC2 address, because the public IP goes away with the instance. I still have the S3 bucket with all the files, both IAM roles, the Lambda site (which keeps working), and the scripts in my GitHub repository. I could launch a new instance with the same user data and get the same site again, but with a new instance ID and IP address.

## 5. Where I adapted things

The page, policies, scripts and function code were written for this assignment using the course material and the official AWS documentation (S3, IAM, EC2 user data and instance metadata, systemd timers, Lambda function URLs). EDIT THIS LINE: say honestly here how you used any other help, including AI tools, according to your instructor's rule.

## 6. Repository layout

```
README.md
collect-evidence.sh
evidence.txt
site/    index.html, style.css, cv.pdf
ec2/     user-data.sh, sync-cv.sh
lambda/  lambda_function.py
iam/     ec2-trust.json, ec2-policy.json, lambda-trust.json, lambda-policy.json
```
