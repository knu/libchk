# $Idaemons$

SCRIPTS=	libchk.rb
MAN=		libchk.1

PREFIX?=	/usr/local
SCRIPTSDIR?=	${PREFIX}/sbin
MANPREFIX?=	${PREFIX}
MANDIR?=	${MANPREFIX}/man/man

.include <bsd.prog.mk>
