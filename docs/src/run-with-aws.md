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

Create a new security group
+ Go to: EC2>Security groups>Create security group
Add inbound rules for the following ports:443, 8080, 80, 3000, 5432, 22, 5050
+ Go to your instance>select your instance>Actions>security>change security group
+ And add the correct security group to the instance.

## Connect to instance with SSH

+ Copy the key file in your default SSH configuration file location (the one VSCode will use)
+ In terminal, go to the folder and run this command to ensure your key is not publicly viewable: 
```
chmod 600 "privatekey.pem"
```

We are using VSCode to connect to the instance: 
+ Install the Remote - SSH Extension for VSCode
+ Open the Command Palette (Ctrl+Shift+P) and type Remote-SSH: Add New SSH Host:
```
ssh -i "privatekey.pem" ubuntu@ec2-111-22-33-44.eu-west-1.compute.amazonaws.com
```
When prompted, select the default SSH configuration file location.
Open the config file and add the location:
```
xIdentityFile ~/.ssh/privatekey.pem
```


## Install Docker on your instance
To install Docker on your new EC2 Ubuntu instance via SSH, follow these steps:

Update your package list:
```
sudo apt-get update
```
Install required dependencies:
```
sudo apt-get install apt-transport-https ca-certificates curl software-properties-common
```
Add Docker's official GPG key:
```
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
```
Add Docker's official repository:
```
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```
Update the package list again:
```
sudo apt-get update
```
Install Docker:
```
sudo apt-get install docker-ce docker-ce-cli containerd.io
```
Verify Docker installation:
```
sudo docker --version
```
Add your user to the docker group to run Docker without sudo:
```
sudo usermod -aG docker ubuntu
```
Then, log out and back in or use the following to apply the changes:
```
newgrp docker
```

Now you can follow the Postgsail process.
