FROM node:22-alpine

USER node
RUN mkdir -p /home/node/code
WORKDIR /home/node/code

COPY package*.json ./
RUN npm ci --ignore-scripts --omit=dev

ADD . .

EXPOSE 8080

CMD ["node", "index.js"]