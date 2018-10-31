#!/bin/bash

# Initialize variables and functions
source /opt/django-DefectDojo/entrypoint_scripts/common/dojo-shared-resources.sh

# This function invocation ensures we're running the script at the right place
verify_cwd

# Create the application DB or recreate it
# ENV vars involved:
    # SQLHOST
    # SQLPORT
    # SQLUSER
    # SQLPWD
    # DBNAME

export AUTO_DOCKER=yes && ensure_application_db
# Adjust the settings.py file
# ENV vars involved:
    # SQLHOST
    # SQLPORT
    # SQLUSER
    # SQLPWD
    # DBNAME

prepare_settings_file

# Ensure, we're running on a supported python version
verify_python_version

# Install the actual application
install_app

# Update ALLOWED_HOSTS with actual route
sed -e 's/ALLOWED_HOSTS.*/ALLOWED_HOSTS = ['\'$APPFQDN\'']/g' -i /opt/django-DefectDojo/dojo/settings/settings.py
echo "Settings have been updated"

# Start application's components
(celery -A dojo worker -l info --concurrency 3 >> /opt/django-DefectDojo/worker.log 2>&1 &)
(celery beat -A dojo -l info  >> /opt/django-DefectDojo/beat.log 2>&1 &)
(python /opt/django-DefectDojo/manage.py runserver 0.0.0.0:8000 >> /opt/django-DefectDojo/dojo.log 2>&1)