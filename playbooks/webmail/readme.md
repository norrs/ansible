# Playbook: webmail

## Generate a password


docker run --rm --entrypoint htpasswd httpd:2 -Bbn norrs testpassword > auth/nginx.htpasswd
