FROM node:22-alpine
WORKDIR /app
RUN apk add --no-cache git
COPY package.json ./
RUN npm install --omit=dev --ignore-scripts
COPY index.mjs ./
ENV NODE_ENV=production
CMD ["npm", "start"]
