#!/bin/bash

# sync up with glacier:/scratch1/arthur/psv/psv
rsync -ru --progress --stats . glacier.lbl.gov:/scratch1/arthur/psv
