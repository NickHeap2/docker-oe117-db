# Build the docker image
```docker build -t oe117-db:0.1 -t oe117-db:latest .```

# Run the container
```docker run -it --rm --name oe117-db -p 20666:20666 -p 20670-20700:20670-20700 oe117-db:latest```

# Run the container with a mapped volume
```docker run -it --rm --name oe117-db -p 20666:20666 -p 20670-20700:20670-20700 -v S:/workspaces/docker-volumes/sports2000:/var/lib/openedge/data oe117-db:latest```

# Run bash in the container
```docker run -it --rm --name oe117-db -p 20666:20666 -p 20670-20700:20670-20700 oe117-db:latest bash```

# Exec bash in the running container
```docker exec -it oe117-db bash```

# Stop the container
```docker stop oe117-db```

# Clean the container
```docker rm oe117-db```

# Install openedge in the container
```/install/oe117/proinst```

# Do an install for the db server
OpenEdge Enterprise RDBMS  
Say No to enabling explorer  
Continue with sql enabled  
English - American as language and make default  
Collation - American,United_States,ISO8859-1,Basic,Basic  
Date format - dmy   
Number format - (comma, period)  
Copy the scripts - yes  

# Copy the response.ini & progress.cfg from the install to use in other images
```docker cp oe117-db:/usr/dlc/install/response.ini .```
```docker cp oe117-db:/usr/dlc/progress.cfg .```
