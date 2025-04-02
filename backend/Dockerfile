# container will be based on the official Node18 image that has Node.js and npm pre-installed
FROM node:18
# creates and/or chanegs into the the working directory /app
WORKDIR /app
# copies package.json and package-lock.json here 
COPY package*.json ./
# install project dependencies from package.json
RUN npm install
# copy all project files into the container - from local project folder into the /app dir
COPY . .
# informs DOcker that the app listens on port 3000 -  ! still need to run the container with -p 3000:3000 to expose it
EXPOSE 3000
# CMD executes node server.js everytime when the container starts
CMD ["node", "server.js"]
