FROM python:3.10-slim-buster

# create and change dir 
WORKDIR /src

# copy source code of the application 
COPY ./Project/udacity_project3 .

# install all dependencies 
RUN apt-get update && apt-get install -y python3-pip && \
    pip3 install --upgrade pip && \
    pip3 install -r requirements.txt

## expected parameters
# APP_PORT      5153
# DB_USERNAME
# DB_PASSWORD
# DB_HOST       "127.0.0.1"
# DB_PORT       "5433"
# DB_NAME       "postgres"
ENTRYPOINT [ "python3", "app.py" ]
