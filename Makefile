# $Idaemons: /home/cvs/libchk/Makefile,v 1.1 2002/09/02 10:37:40 knu Exp $

SCRIPTS=	libchk.rb
MAN=		libchk.1

PREFIX?=	/usr/local
SCRIPTSDIR?=	${PREFIX}/sbin
MANPREFIX?=	${PREFIX}
MANDIR?=	${MANPREFIX}/man/man

archive:
	rev=`ident libchk.rb | awk '$$3 != "" {print $$3}'`; \
	name=libchk-$$rev; \
	cvs export -rHEAD -d$$name libchk; \
	tar jcf $$name.tar.bz2 $$name; \
	rm -r $$name

release:
	rev=`ident libchk.rb | awk '$$3 != "" {print $$3}'`; \
	name=libchk-$$rev; \
	cp -p $$name.tar.bz2 ~/distfiles/; \
	mv $$name.tar.bz2 ~/ff/ftp/; \
	syncfreefall -f

.include <bsd.prog.mk>
