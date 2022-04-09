FROM node:16-alpine

USER node
RUN mkdir -p /home/node/code
WORKDIR /home/node/code

COPY package*.json ./
RUN npm ci --ignore-scripts --production

ADD . .

EXPOSE 8080

CMD ["node", "index.js"]