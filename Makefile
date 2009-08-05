# $Id$

SCRIPTS=	libchk.rb
MAN=		libchk.1

PREFIX?=	/usr/local
SCRIPTSDIR?=	${PREFIX}/sbin
MANPREFIX?=	${PREFIX}
MANDIR?=	${MANPREFIX}/man/man

archive:
	rev=`./libchk.rb --help | awk '$$1=="version"{print $$2}'`; \
	name=libchk-$$rev; \
	svn export -rHEAD . $$name; \
	tar jcf $$name.tar.bz2 $$name; \
	rm -r $$name

release:
	rev=`./libchk.rb --help | awk '$$1=="version"{print $$2}'`; \
	name=libchk-$$rev; \
	cp -p $$name.tar.bz2 ~/distfiles/; \
	mv $$name.tar.bz2 ~/src/remote/host/freefall.freebsd.org/ftp/; \
	(cd ~/src/remote && ./do upload freefall.freebsd.org); \
	man2html libchk.1 > /home/www/www.idaemons.org/data/projects/libchk/man.html
	e /home/www/www.idaemons.org/data/projects/libchk/index.html

.include <bsd.prog.mk>
