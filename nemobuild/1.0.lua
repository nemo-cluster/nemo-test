help([==[

Description
===========
EasyBuild is a software build and installation framework
written in Python that allows you to install software in a structured,
repeatable and robust way.


More information
================
 - Homepage: http://easybuilders.github.com/easybuild/
]==])

whatis([==[Description: EasyBuild is a software build and installation framework
written in Python that allows you to install software in a structured,
repeatable and robust way.]==])
whatis([==[Homepage: http://easybuilders.github.com/easybuild/]==])
whatis([==[URL: http://easybuilders.github.com/easybuild/]==])

conflict("EasyBuild-custom")

depends_on("EasyBuild")

--- Custum stuff
setenv("EASYBUILD_PREFIX", pathJoin(os.getenv("HOME"), "nemobuild"))
setenv("EASYBUILD_CONFIGFILES","{{DEPLOYDIR}}/config.cfg")
append_path("EASYBUILD_ROBOT_PATHS", "{{DEPLOYDIR}}/easyconfigs")
append_path("EASYBUILD_ROBOT_PATHS", pathJoin(os.getenv("EBROOTEASYBUILD"), "easybuild/easyconfigs"))
prepend_path("MODULEPATH", pathJoin(os.getenv("HOME"),"nemobuild/modules/all"))

