## Self AWS cloud hosted setup example

In this guide we install, setup and run a postgsail project on an AWS instance in the cloud.

## On AWS Console
***Launch an instance on AWS EC2***
With the following settings:
+ Ubuntu
+ Instance type: t2.small
+ Create a new key pair: 
    + key pair type: RSA
    + Private key file format: .pem
+ The key file is stored for later use

+ Allow SSH traffic from: Anywhere
+ Allow HTTPS traffic from the internet
+ Allow HTTP traffic from the internet

Configure storage:
The standard storage of 8GiB is too small so change this to 16GiB.

***Create a new security group***
Go to: EC2>Security groups>Create security group
Add inbound rules for the following ports:443, 8080, 80, 3000, 5432, 22, 5050
Go to your instance>select your instance>Actions>security>change security group
And add the correct security group to the instance.

## Connect to instance with SSH

Copy the key file in your default SSH configuration file location (the one VSCode will use)
In terminal, go to the folder and run this command to ensure your key is not publicly viewable: 
```chmod 600 "privatekey.pem"```

We are using VSCode to connect to the instance: 
Install the Remote - SSH Extension for VSCode;
Open the Command Palette (Ctrl+Shift+P) and type Remote-SSH: Add New SSH Host:
```ssh -i "privatekey.pem" ubuntu@ec2-111-22-33-44.eu-west-1.compute.amazonaws.com```
When prompted, select the default SSH configuration file location.
Open the config file and add the location:
```xIdentityFile ~/.ssh/privatekey.pem```


## Install Docker on your instance
To install Docker on your new EC2 Ubuntu instance via SSH, follow these steps:

Update your package list:
```sudo apt-get update```
Install required dependencies:
```sudo apt-get install apt-transport-https ca-certificates curl software-properties-common```
Add Docker's official GPG key:
```curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg```
Add Docker's official repository:
```echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null```
Update the package list again:
```sudo apt-get update```
Install Docker:
```sudo apt-get install docker-ce docker-ce-cli containerd.io```
Verify Docker installation:
```sudo docker --version```
Add your user to the docker group to run Docker without sudo:
```sudo usermod -aG docker ubuntu```
Then, log out and back in or use the following to apply the changes:
```newgrp docker```



## Install Postgsail 
+ Git clone the postgsail repo:
```git clone https://github.com/xbgmsharp/postgsail.git```

## Edit environment variables
Copy the example.env file and edit the environment variables:
```cd postgsail```
```cp .env.example .env```
```nano .env```

***POSTGRES_USER***
Come up with a unique username for the database user. This will be used in the docker image when it’s started up. Nothing beyond creating a unique username and password is required here.
This environment variable is used in conjunction with `POSTGRES_PASSWORD` to set a user and its password. This variable will create the specified user with superuser power and a database with the same name.

https://github.com/docker-library/docs/blob/master/postgres/README.md

***POSTGRES_PASSWORD***
This should be a good password. It will be used for the postgres user above. Again this is used in the docker image.
This environment variable is required for you to use the PostgreSQL image. It must not be empty or undefined. This environment variable sets the superuser password for PostgreSQL. The default superuser is defined by the POSTGRES_USER environment variable.

***POSTGRES_DB***
This is the name of the database within postgres. You can leave it named postgres but give it a unique name if you like. The schema will be loaded into this database and all data will be stored within it. Since this is used inside the docker image the name really doesn’t matter. If you plan to run additional databases within the image, then you might care.
This environment variable can be used to define a different name for the default database that is created when the image is first started. If it is not specified, then the value of `POSTGRES_USER` will be used.

***PGSAIL_APP_URL***
This is the webapp (webui) entrypoint, typically the public DNS or IP
```PGSAIL_APP_URL=http://localhost:8080```


***PGSAIL_API_URL***
This is the URL to your API on your instance on port 3000:
```PGSAIL_API_URL=PGSAIL_API_URL=http://localhost:3000```

***PGSAIL_AUTHENTICATOR_PASSWORD***
This password is used as part of the database access configuration. It’s used as part of the access URI later on. (Put the same password in both lines.)

***PGSAIL_GRAFANA_PASSWORD***
This password is used for the grafana service

***PGSAIL_GRAFANA_AUTH_PASSWORD***
??This password is used for user authentication on grafana?

***PGSAIL_EMAIL_FROM***
***PGSAIL_EMAIL_SERVER***
***PGSAIL_EMAIL_USER***
***PGSAIL_EMAIL_PASS***
Pgsail does not include a built in email service - only hooks to send email via an existing server.
We use gmail as a third party email service:
PGSAIL_EMAIL_FROM=email@gmail.com
PGSAIL_EMAIL_SERVER=smtp.gmail.com
PGSAIL_EMAIL_USER=email@gmail.com
You need to get the PGSAIL_EMAIL_PASS from your gmail account security settings: it is not the account password, instead you need to make an "App password"

***PGRST_JWT_SECRET***
This secret key must be at least 32 characters long, you can create a random key with the following command:
```cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w 42 | head -n 1```

***Other ENV variables***
```
PGSAIL_PUSHOVER_APP_TOKEN
PGSAIL_PUSHOVER_APP
PGSAIL_TELEGRAM_BOT_TOKEN
PGSAIL_AUTHENTICATOR_PASSWORD=password
PGSAIL_GRAFANA_PASSWORD=password
PGSAIL_GRAFANA_AUTH_PASSWORD=password
#PGSAIL_PUSHOVER_APP_TOKEN= Comment if not use
#PGSAIL_PUSHOVER_APP_URL= Comment if not use
#PGSAIL_TELEGRAM_BOT_TOKEN= Comment if not use
```

## Run the project
If needed, add your user to the docker group to run Docker without sudo:
```sudo usermod -aG docker ubuntu```
Then, log out and back in or use the following to apply the changes:
```newgrp docker```


Step 1. Import the SQL schema, execute:
```docker compose up db```
Step 2. Launch the full backend stack (db, api), execute:
```docker compose up db api```
Step 3. Launch the frontend webapp
```docker compose up web```

Open browser and navigate to your PGSAIL_APP_URL, you should see the postgsail login screen now:
http://ec2-11-234-567-890.eu-west-1.compute.amazonaws.com::8080


## Additional SQL setup
Aditional setup will be required.
There is no useraccount yet, also cronjobs need to be activated.
We'll do that by using pgadmin.

***Run pgadmin***
First add two more vars to your env. file:
```PGADMIN_DEFAULT_EMAIL=setup@setup.com```
```PGADMIN_DEFAULT_PASSWORD=123456```
And add pgadmin to the docker-compose.yml file under "services":
```

```