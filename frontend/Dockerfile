FROM node:lts-alpine

# install simple http server for serving static content
RUN npm install -g http-server

# copy both 'package.json' and 'package-lock.json' (if available)
COPY package*.json ./

# install project dependencies
RUN npm install

# copy project files and folders to the current working directory (i.e. 'frontend' folder)
COPY . .

# build app for production with minification
RUN npm run build

EXPOSE 80
CMD http-server dist -p 80

# docker build -t endrizzimarco/com3026-frontend frontend
# docker push endrizzimarco/com3026-frontend:latest