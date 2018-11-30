#!/bin/bash

# Initialize variables and functions
source /opt/django-DefectDojo/entrypoint_scripts/common/dojo-shared-resources.sh

# This function invocation ensures we're running the script at the right place
required_fs_objects="manage.py setup.bash dojo"
for obj in $required_fs_objects; do
    if [ ! -e $obj ]; then
        echo "Couldn't find '$obj' in $DOJO_ROOT_DIR; Please run this script at the application's root directory" >&2
        exit 1
    fi
done

# Ensure, we're running on a supported python version
# Detect Python version
PYV=`python -c "import sys;t='{v[0]}.{v[1]}'.format(v=list(sys.version_info[:2]));sys.stdout.write(t)";`
if [[ "$PYV"<"2.7" ]]; then
    echo "ERROR: DefectDojo requires Python 2.7+"
    exit 1;
else
    echo "Leaving Django 1.x.y requirement"
fi

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
# python manage.py loaddata system_settings
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

echo "=============================================================================="
echo "Creating Dojo Super User"
echo "=============================================================================="
echo

#setup default admin dojo user
if [ -z "$DEFECTDOJO_ADMIN_USER" ]; then
    DEFECTDOJO_ADMIN_USER='admin'
fi
if [ -z "$DOJO_ADMIN_EMAIL" ]; then
    DOJO_ADMIN_EMAIL='admin@localhost.local'
fi
if [ -z "$DEFECTDOJO_ADMIN_PASSWORD" ]; then
    DEFECTDOJO_ADMIN_PASSWORD=`LC_CTYPE=C tr -dc A-Za-z0-9_\!\@\#\$\%\^\&\*\(\)-+ < /dev/urandom | head -c 32 | xargs`
fi
#creating default admin user
echo "from django.contrib.auth.models import User; User.objects.create_superuser('$DEFECTDOJO_ADMIN_USER', '$DOJO_ADMIN_EMAIL', '$DEFECTDOJO_ADMIN_PASSWORD')" | ./manage.py shell
if [ $? = 0 ]
then
    echo "Superuser $DEFECTDOJO_ADMIN_USER has been created"
else
    echo "Superuser remaind the same"
fi
    
# Start application's components
celery -A dojo worker -l info --concurrency 3 >> /opt/django-DefectDojo/worker.log 2>&1 &
echo "Celery worker was started"
celery beat -A dojo -l info  >> /opt/django-DefectDojo/beat.log 2>&1 &
echo "Celery Beat was started"
python /opt/django-DefectDojo/manage.py runserver 0.0.0.0:8000 >> /opt/django-DefectDojo/dojo.log 2>&1