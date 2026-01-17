# fedora-container

If you already have `oscap` installed on your current host, you don't need to worry about this folder. If you're on Windows, you can also simply use a Fedora WSL container to perform the scans.

The `Dockerfile` in this folder will build a Fedora 43 container that you can use to run `oscap` scans against the Oracle Linux 9 endpoint that is set up via `/scripts/setup.sh`.

The container must be started _after_ running `/scripts/setup.sh`. The setup script provisions the docker network used to conduct the scans.

---

To build the container image run:
`docker build -t openscap-img .`

To run the container:
`docker run -d --network scap-network --name openscap1 -v ../policy:/policy openscap-img`

To obtain a shell within the container, run:
`docker exec -it openscap1 /bin/bash`

You can now run scans against the Oracle Linux 9 endpoint.
