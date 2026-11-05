# Environment management

Create the working directory
```
PROJDIR=/data/Wilson_Lab/projects/ConGen_VGP_Phase1
DATADIR=/data/Wilson_Lab/data/ConGen_VGP_Phase1
GITDIR=${PROJDIR}/scripts/
SCRIPTDIR=${PROJDIR}/scripts/SexChr_ConGen_VGP_Phase1

mkdir -p $PROJDIR $DATADIR $SCRIPTDIR

cd ${GITDIR}
git clone https://github.com/dannyjackson/SexChr_ConGen_VGP_Phase1
```
Run at the top of every markdown file
```
PROJDIR=/data/Wilson_Lab/projects/ConGen_VGP_Phase1
DATADIR=/data/Wilson_Lab/data/ConGen_VGP_Phase1
GITDIR=${PROJDIR}/scripts/
SCRIPTDIR=${PROJDIR}/scripts/SexChr_ConGen_VGP_Phase1

cd ${SCRIPTDIR} && git pull
cd ${PROJDIR}
```