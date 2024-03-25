FROM elixir:alpine 

COPY . .
RUN mix local.hex --force
RUN mix deps.get

EXPOSE 2053
CMD mix run --no-halt

# docker build -t endrizzimarco/com3026-backend backend  
# docker push endrizzimarco/com3026-backend:latest