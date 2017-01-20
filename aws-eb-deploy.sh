#!/bin/bash
#
# Author: Benoit Hediard
# Email: ben@benorama.com
# Creation date: 2015-02-26
# Version: 1.0
#
# Usage:
#
# Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY env variables.
#
# Set AWS_REGION and BEANSTALK_APP env variables or add the following properties to you application.properties:
# aws.region=eu-west-1
# beanstalk.app=MyApp
#
# Optional settings, if you want to deploy to the same environment each time, set 'beanstalk.env':
# beanstalk.env=staging
#
# Optional settings, if you want to create a new environment for each version deployment (and use swap url mechanism to release your app), set any 'beanstalk.template':
# beanstalk.template=default
#
# The env name will be dynamically generated from 'beanstalk.app' and 'grails app.version' (ex.: if grails app version is 1.2.0, env name will be MyApp-1-2-0)
# If the environment does not exist, it will be automatically created with given 'beanstalk.template' (saved configuration)
#
# Run ./aws-eb-deploy.sh
#

# AWS config
export BEANSTALK_APP=MyApp
export AWS_REGION=ap-south-1a
export S3_BUCKET=pesample
if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo "AWS_ACCESS_KEY_ID env variable must be set"
    exit 1
fi
if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "AWS_SECRET_ACCESS_KEY env variable must be set"
    exit 1
fi
if [ -z "$AWS_REGION" ]; then
    AWS_REGION=`sed '/^\#/d' application.properties | grep 'aws.region'  | tail -n 1 | cut -d "=" -f2-`
    if [ -z "$AWS_REGION" ]; then
        echo "aws.region must be defined in application.properties or AWS_REGION env variable must be set"
        exit 1
    fi
fi

# Grails config
GRAILS_APP_NAME=`sed '/^\#/d' application.properties | grep 'app.name'  | tail -n 1 | cut -d "=" -f2-`
GRAILS_APP_VERSION=`sed '/^\#/d' application.properties | grep 'app.version'  | tail -n 1 | cut -d "=" -f2-`
GRAILS_WAR_FILE_NAME=${GRAILS_APP_NAME}-${GRAILS_APP_VERSION}.war
GRAILS_WAR_FILE_PATH=./target/${GRAILS_WAR_FILE_NAME}
if [ ! -f $GRAILS_WAR_FILE_PATH ]; then
    echo "War file not found in target directory, please run 'grails war' first!"
    exit 1
fi

# Get war timestamp
if [ "$OSTYPE" = "darwin14" ]
then
    # OSX BSD stat
    GRAILS_WAR_TIME=`stat -f %m $GRAILS_WAR_FILE_PATH`
else
    # Linux stat
    GRAILS_WAR_TIME=`stat -c %Y $GRAILS_WAR_FILE_PATH`
fi


# Beanstalk config
if [ -z "$BEANSTALK_APP" ]; then
    BEANSTALK_APP=`sed '/^\#/d' application.properties | grep 'beanstalk.app'  | tail -n 1 | cut -d "=" -f2-`
    if [ -z "$BEANSTALK_APP" ]; then
        echo "beanstalk.app must be defined in application.properties or BEANSTALK_APP env variable must be set"
        exit 1
    fi
fi

if [ -z "$BEANSTALK_ENV" ]; then
    BEANSTALK_ENV=`sed '/^\#/d' application.properties | grep 'beanstalk.env'  | tail -n 1 | cut -d "=" -f2-`
    if [ -z "$BEANSTALK_ENV" ]; then
        # Build beanstalk env name from app version
        BEANSTALK_ENV=`echo ${BEANSTALK_APP}-${GRAILS_APP_VERSION//./-}`
    fi
fi

# Build beanstalk version label
if [[ "$GRAILS_APP_VERSION" == *"SNAPSHOT" ]]
then
    # Add war timestamp for snapshots
    BEANSTALK_VERSION_LABEL=${GRAILS_APP_VERSION}-${GRAILS_WAR_TIME}
else
    BEANSTALK_VERSION_LABEL=${GRAILS_APP_VERSION}
fi

# Finding S3 bucket to upload WAR
S3_BUCKET=`aws elasticbeanstalk create-storage-location --region ${AWS_REGION} --output text`
S3_KEY=${GRAILS_APP_NAME}-${GRAILS_APP_VERSION}-${GRAILS_WAR_TIME}.war

# Upload to S3
echo "Uploading $GRAILS_WAR_FILE_NAME to S3..."
aws s3 cp ${GRAILS_WAR_FILE_PATH} s3://${S3_BUCKET}/${S3_KEY} --region ${AWS_REGION}

# Create application version
echo "Creating application version $BEANSTALK_VERSION_LABEL"
aws elasticbeanstalk create-application-version --application-name ${BEANSTALK_APP} --version-label ${BEANSTALK_VERSION_LABEL} --source-bundle S3Bucket=${S3_BUCKET},S3Key=${S3_KEY} --region ${AWS_REGION} --output table

# Check if environment exists
BEANSTALK_ENV_DESCRIPTION=`aws elasticbeanstalk describe-environments --environment-names ${BEANSTALK_ENV} --region ${AWS_REGION} --output text`

if [ -z "$BEANSTALK_ENV_DESCRIPTION" ];
then
    # Create environment
    BEANSTALK_ENV_TEMPLATE=`sed '/^\#/d' application.properties | grep 'beanstalk.template'  | tail -n 1 | cut -d "=" -f2-`
    if [ -z "$BEANSTALK_ENV_TEMPLATE" ]; then
        BEANSTALK_ENV_TEMPLATE=default
    fi
    echo "Creating environment $BEANSTALK_ENV with template $BEANSTALK_ENV_TEMPLATE"
    aws elasticbeanstalk create-environment --application-name ${BEANSTALK_APP} --environment-name ${BEANSTALK_ENV} --template-name ${BEANSTALK_ENV_TEMPLATE} --version-label ${BEANSTALK_VERSION_LABEL} --region ${AWS_REGION} --output table
else
    # Update environment
    echo "Updating environment $BEANSTALK_ENV"
    aws elasticbeanstalk update-environment --environment-name ${BEANSTALK_ENV} --version-label ${BEANSTALK_VERSION_LABEL} --region ${AWS_REGION} --output table
fi
