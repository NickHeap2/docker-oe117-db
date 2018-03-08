# docker-oe117-db

## docker commands

### Build the docker image

```bash
docker build -t oe117-db:0.1 -t oe117-db:latest .
```

### Run the container

```bash
docker run -it --rm --name oe117-db -p 20666:20666 -p 20670-20700:20670-20700 oe117-db:latest
```

### Run the container with a mapped volume for data

```bash
docker run -it --rm --name oe117-db -p 20666:20666 -p 20670-20700:20670-20700 -v S:/workspaces/docker-volumes/sports2000:/var/lib/openedge/data oe117-db:latest
```

### Run the container with a mapped volume for data and one for code like triggers

```bash
docker run -it --rm --name oe117-db -p 20666:20666 -p 20670-20700:20670-20700 -v S:/workspaces/docker-volumes/sports2000:/var/lib/openedge/data -v S:/workspaces/docker-volumes/sports2000/code:/var/lib/openedge/code 
oe117-db:latest
```

### Run the container with a mapped volume and rebuild database from sports2000

```bash
docker run -it --rm --name oe117-db -p 20666:20666 -p 20670-20700:20670-20700 -v S:/workspaces/docker-volumes/sports2000:/var/lib/openedge/data -e OPENEDGE_REBUILD=true -e OPENEDGE_BASE=sports2000 oe117-db:latest
```

### Run bash in the container

```bash
docker run -it --rm --name oe117-db -p 20666:20666 -p 20670-20700:20670-20700 oe117-db:latest bash
```

### Exec bash in the running container

```bash
docker exec -it oe117-db bash
```

### Stop the container

```bash
docker stop oe117-db
```

### Clean the container

```bash
docker rm oe117-db
```
