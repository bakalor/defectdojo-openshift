#!/bin/bash

# Initialize variables and functions
source /opt/django-DefectDojo/entrypoint_scripts/common/dojo-shared-resources.sh

# This function invocation ensures we're running the script at the right place
verify_cwd

# Ensure, we're running on a supported python version
verify_python_version

# Create the application DB or recreate it
# ENV vars involved:
    # SQLHOST
    # SQLPORT
    # SQLUSER
    # SQLPWD
    # DBNAME

if [ -z "$SQLHOST" ]; then
    echo "SQL Host not provided, exiting"
    exit 1
fi
if [ -z "$SQLPORT" ]; then
    SQLPORT="5432"
fi
if [ -z "$SQLUSER" ]; then
    SQLUSER="root"
fi
if [ -z "$SQLPWD" ]; then
    echo "SQL Password not provided, exiting"
    exit 1
fi
if [ -z "$DBNAME" ]; then
    DBNAME="dojodb"
fi
if [ "$( PGPASSWORD=$SQLPWD psql -h $SQLHOST -p $SQLPORT -U $SQLUSER -tAc "SELECT 1 FROM pg_database WHERE datname='$DBNAME'" )" = '1' ]
    then
        echo "Database $DBNAME already exists!"
        if [[ ! $FLUSH_DB =~ ^[nN]o$ ]]; then
            PGPASSWORD=$SQLPWD dropdb $DBNAME -h $SQLHOST -p $SQLPORT -U $SQLUSER
            PGPASSWORD=$SQLPWD createdb $DBNAME -h $SQLHOST -p $SQLPORT -U $SQLUSER
            echo "Database $DBNAME has been re-created!"
        else
            echo "Existent database $DBNAME has been used"
        fi
else
    PGPASSWORD=$SQLPWD createdb $DBNAME -h $SQLHOST -p $SQLPORT -U $SQLUSER
    if [ $? = 0 ]
    then
        echo "Created database $DBNAME."
    else
        echo "Error! Failed to create database $DBNAME. Check your credentials."
    fi
fi

# Adjust the settings.py file
# ENV vars involved:
    # SQLHOST
    # SQLPORT
    # SQLUSER
    # SQLPWD
    # DBNAME

if [ -z "$EXTERNAL_SECRETS" ]; then
    echo "Using internal settings generation mechanism"
    prepare_settings_file
else
    # Copy settings file
    echo "Using externally provided settings"
    cp dojo/settings/settings.dist.py dojo/settings/settings.py
fi


# Install the actual application
echo "Installation has started"
python manage.py makemigrations dojo
python manage.py makemigrations --merge --noinput
python manage.py migrate
python manage.py loaddata product_type
python manage.py loaddata test_type
python manage.py loaddata development_environment
python manage.py loaddata system_settings
python manage.py loaddata benchmark_type
python manage.py loaddata benchmark_category
python manage.py loaddata benchmark_requirement
python manage.py loaddata language_type
python manage.py loaddata objects_review
python manage.py loaddata regulation
python manage.py installwatson
python manage.py buildwatson

# Install yarn packages
cd components && yarn && cd ..

python manage.py collectstatic --noinput

# Create superuser
if [[ ! $FLUSH_DB =~ ^[nN]o$ ]]; then
    createadmin
else
    echo "Superuser remaind the same"
fi
# Start application's components
(celery -A dojo worker -l info --concurrency 3 >> /opt/django-DefectDojo/worker.log 2>&1 &)
(celery beat -A dojo -l info  >> /opt/django-DefectDojo/beat.log 2>&1 &)
(python /opt/django-DefectDojo/manage.py runserver 0.0.0.0:8000 >> /opt/django-DefectDojo/dojo.log 2>&1)