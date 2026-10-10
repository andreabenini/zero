# zero-login is compiled on the target machine by login/install.sh, or inside a
# package's build root, and is never committed. -lpam is the only library it
# links.
#
# Every path that gets baked into the binary or the unit comes from a variable
# here, so a hand-install and a distribution package differ only in what they
# pass in:
#
#   make                                    /opt/zero - the hand-install default
#   make zerodir=/usr/lib/zero              what a PKGBUILD, .deb or .rpm wants
#   make DESTDIR=/tmp/build install         staged install, for packaging
#
# /etc/zero/login is deliberately NOT a variable. It is config, it is correct on
# every distribution, and zero-login.c, profile/login.sh, profile/power.sh,
# profile/autostart and profile/waybar/config-login all name it literally -
# there is no substitution step for the shell files, so a variable here could
# only ever disagree with them.

CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra
LDLIBS   = -lpam
INSTALL ?= install

DESTDIR     ?=
zerodir     ?= /opt/zero
pamdir      ?= /etc/pam.d
unitdir     ?= /etc/systemd/system
sysusersdir ?= /usr/lib/sysusers.d

# Fixed by design - see the note above.
profiledir = /etc/zero/login

# The project tree that gets copied next to the binary. standalone.sh is what
# the parent execs after a successful login, and it needs lib/ and defaults/
# beside it.
projectdir ?= ..
TREE        = standalone.sh nested.sh lib defaults docs

# The one path the C has to know at build time: standalone.sh is exec'd by
# absolute path after the fork, so it cannot be found on PATH.
CPPFLAGS += -DSTANDALONE='"$(zerodir)/standalone.sh"'

# `all` is the build machine's half, `install` the target's. They are separate
# on purpose: the tarball carries a compiled zero-login, so install.sh never
# builds and a test machine needs no compiler and no PAM headers. Nothing in
# the install targets depends on `all` - a missing artifact is an error, not a
# reason to start compiling on the target.
all: zero-login zero-login.service

zero-login: zero-login.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -o $@ $< $(LDLIBS)

# @ZERODIR@ is the only substitution the unit needs: it names the binary and
# the documentation by absolute path.
zero-login.service: zero-login.service.in
	sed 's|@ZERODIR@|$(zerodir)|g' $< > $@

# The login manager's own artifacts. Everything root-owned and world-readable;
# nothing here is secret and the greeter reads it as uid `zero`.
install-login:
	@test -x zero-login || { echo "login/zero-login is not built - run login/package.sh on the build machine" >&2; exit 1; }
	@test -f zero-login.service || { echo "login/zero-login.service is not generated - run login/package.sh on the build machine" >&2; exit 1; }
	$(INSTALL) -d -m 0755 $(DESTDIR)$(zerodir)/login
	$(INSTALL) -m 0755 zero-login $(DESTDIR)$(zerodir)/login/zero-login
	$(INSTALL) -D -m 0644 pam/zero-login   $(DESTDIR)$(pamdir)/zero-login
	$(INSTALL) -D -m 0644 pam/zero-greeter $(DESTDIR)$(pamdir)/zero-greeter
	$(INSTALL) -D -m 0644 zero-login.service $(DESTDIR)$(unitdir)/zero-login.service
	$(INSTALL) -D -m 0644 zero-login.sysusers $(DESTDIR)$(sysusersdir)/zero-login.conf

# The greeter profile, copied verbatim. configurator.py is never run against
# this directory - see docs/LOGIN.md.
install-profile:
	$(INSTALL) -d -m 0755 $(DESTDIR)$(profiledir)/waybar
	$(INSTALL) -m 0755 profile/autostart $(DESTDIR)$(profiledir)/autostart
	$(INSTALL) -m 0755 profile/login.sh  $(DESTDIR)$(profiledir)/login.sh
	$(INSTALL) -m 0755 profile/power.sh  $(DESTDIR)$(profiledir)/power.sh
	$(INSTALL) -m 0644 profile/look.sh   $(DESTDIR)$(profiledir)/look.sh
	$(INSTALL) -m 0644 profile/rc.xml    $(DESTDIR)$(profiledir)/rc.xml
	$(INSTALL) -m 0644 profile/menu.xml  $(DESTDIR)$(profiledir)/menu.xml
	$(INSTALL) -m 0644 profile/avatar.png $(DESTDIR)$(profiledir)/avatar.png
	$(INSTALL) -m 0644 profile/waybar/config-login    $(DESTDIR)$(profiledir)/waybar/config-login
	$(INSTALL) -m 0644 profile/waybar/style-login.css $(DESTDIR)$(profiledir)/waybar/style-login.css

# A copy of the project, because the parent execs standalone.sh as the user who
# logged in and the tree has to be readable by every account that can log in.
# tar rather than cp -r: __pycache__ has to stay out of an installed tree.
#
# The modes are re-applied only to what was just copied, rather than to the
# whole of $(zerodir): a reinstall would otherwise find login/zero-login sitting
# there from last time and take its execute bit off.
install-tree:
	$(INSTALL) -d -m 0755 $(DESTDIR)$(zerodir)
	tar -cf - -C $(projectdir) \
	    --exclude='__pycache__' --exclude='*.pyc' --exclude='*.pyo' \
	    $(TREE) | tar -xf - -C $(DESTDIR)$(zerodir)
	for f in $(TREE); do \
	    find $(DESTDIR)$(zerodir)/$$f -type d -exec chmod 0755 {} + ; \
	    find $(DESTDIR)$(zerodir)/$$f -type f -exec chmod 0644 {} + ; \
	done
	chmod 0755 $(DESTDIR)$(zerodir)/standalone.sh $(DESTDIR)$(zerodir)/nested.sh

install: install-tree install-login install-profile

clean:
	rm -f zero-login zero-login.service

.PHONY: all clean install install-login install-profile install-tree
