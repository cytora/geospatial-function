# geospatial-lambda

This service aims to provide Geospatial Functionality on top of RDS PostgreSQL/PostGIS. The API provides basic
discovery endpoint on top of registered geospatial layers as well as intersect endpoint for intersect given Lat, Lon
specific layer defined by name

## Setup
The team recommends installing [Homebrew](https://brew.sh/) or another package manager
if possible for easier installation and upgrade management.

## Environment setup

This is a python application and it needs the following tools installed:

* python3
* virtualenv

These tools can be installed via `homebrew` and `pip`:

```sh
$ brew update
$ brew install python@3.9
$ pip3 install virtualenv
```

The repository is located at [risk-stream-service](https://github.com/cytora/risk-stream-service/)
and can be checked out using git.

```sh
$ git clone git@github.com:cytora/risk-stream-service.git
```

To configure the service several environment variables must be set. The 
`env.example.sh` file that contains the names of the variables
and a brief description of how the variables are used. To configure your local 
environment please copy the example file and fill the variable marked with
`__EMPTY__`.
To facilitate the creation of the most common configurations a `env.sh` file 
can be downloaded from 1pass stored under the key `risk stream dev configurations`.

```sh
$ cp env.example.sh env.sh # copy the content of the 1pass entry into the new file
$ # alternatively download the pre-filled file from 1pass (see above)
$ source env.sh # this will load the variables into your shell's environment
```

The **first time** the project is executed a **virtualenv** should be created and 
the project's dependencies must be installed:

```sh
$ virtualenv venv                 # creates the virtualenv
$ source venv/bin/activate        # activates it
$ pip install -r requirements.txt # install the dependencies
```

NOTE: before installing requirements.txt, if you are on a Mac replace 'python-magic' -> 'python-magic-bin' in that file

Now we should be able to start the service locally.

```sh
$ python local.py
$ open http://localhost:8080 # opens a browser window
```
