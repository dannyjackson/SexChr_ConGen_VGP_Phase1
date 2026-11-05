# Environment management

Create the working directory
```
PROJDIR=/data/Wilson_Lab/projects/ConGen_VGP_Phase1
DATADIR=/data/Wilson_Lab/data/ConGen_VGP_Phase1
GITDIR=${PROJDIR}/scripts/
SCRIPTDIR=${PROJDIR}/scripts/SexChr_ConGen_VGP_Phase1
REFLISTS=/data/Wilson_Lab/projects/ConGen_VGP_Phase1/reference_lists

mkdir -p $PROJDIR $DATADIR $SCRIPTDIR $REFLISTS

cd ${GITDIR}
git clone https://github.com/dannyjackson/SexChr_ConGen_VGP_Phase1
```
Run at the top of every markdown file
```
PROJDIR=/data/Wilson_Lab/projects/ConGen_VGP_Phase1
DATADIR=/data/Wilson_Lab/data/ConGen_VGP_Phase1
GITDIR=${PROJDIR}/scripts/
SCRIPTDIR=${PROJDIR}/scripts/SexChr_ConGen_VGP_Phase1
REFLISTS=/data/Wilson_Lab/projects/ConGen_VGP_Phase1/reference_lists

cd ${SCRIPTDIR} && git pull
cd ${PROJDIR}
```