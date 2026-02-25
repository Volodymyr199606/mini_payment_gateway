
SHELL = /bin/sh

# V=0 quiet, V=1 verbose.  other values don't work.
V = 0
V0 = $(V:0=)
Q1 = $(V:1=)
Q = $(Q1:0=@)
ECHO1 = $(V:1=@ :)
ECHO = $(ECHO1:0=@ echo)
NULLCMD = :

#### Start of system configuration section. ####

srcdir = .
topdir = /C/Ruby40-x64/include/ruby-4.0.0
hdrdir = $(topdir)
arch_hdrdir = /C/Ruby40-x64/include/ruby-4.0.0/x64-mingw-ucrt
PATH_SEPARATOR = :
VPATH = $(srcdir):$(arch_hdrdir)/ruby:$(hdrdir)/ruby
prefix = $(DESTDIR)/C/Ruby40-x64
rubysitearchprefix = $(rubylibprefix)/$(sitearch)
rubyarchprefix = $(rubylibprefix)/$(arch)
rubylibprefix = $(libdir)/$(RUBY_BASE_NAME)
exec_prefix = $(prefix)
vendorarchhdrdir = $(vendorhdrdir)/$(sitearch)
sitearchhdrdir = $(sitehdrdir)/$(sitearch)
rubyarchhdrdir = $(rubyhdrdir)/$(arch)
vendorhdrdir = $(rubyhdrdir)/vendor_ruby
sitehdrdir = $(rubyhdrdir)/site_ruby
rubyhdrdir = $(includedir)/$(RUBY_VERSION_NAME)
vendorarchdir = $(vendorlibdir)/$(sitearch)
vendorlibdir = $(vendordir)/$(ruby_version)
vendordir = $(rubylibprefix)/vendor_ruby
sitearchdir = $(sitelibdir)/$(sitearch)
sitelibdir = $(sitedir)/$(ruby_version)
sitedir = $(rubylibprefix)/site_ruby
rubyarchdir = $(rubylibdir)/$(arch)
rubylibdir = $(rubylibprefix)/$(ruby_version)
sitearchincludedir = $(includedir)/$(sitearch)
archincludedir = $(includedir)/$(arch)
sitearchlibdir = $(libdir)/$(sitearch)
archlibdir = $(libdir)/$(arch)
ridir = $(datarootdir)/$(RI_BASE_NAME)
modular_gc_dir = $(DESTDIR)
mandir = $(datarootdir)/man
localedir = $(datarootdir)/locale
libdir = $(exec_prefix)/lib
psdir = $(docdir)
pdfdir = $(docdir)
dvidir = $(docdir)
htmldir = $(docdir)
infodir = $(datarootdir)/info
docdir = $(datarootdir)/doc/$(PACKAGE)
oldincludedir = $(DESTDIR)/usr/include
includedir = $(prefix)/include
runstatedir = $(localstatedir)/run
localstatedir = $(prefix)/var
sharedstatedir = $(prefix)/com
sysconfdir = $(DESTDIR)
datadir = $(datarootdir)
datarootdir = $(prefix)/share
libexecdir = $(exec_prefix)/libexec
sbindir = $(exec_prefix)/sbin
bindir = $(exec_prefix)/bin
archdir = $(rubyarchdir)


CC_WRAPPER = 
CC = gcc
CXX = g++
LIBRUBY = lib$(RUBY_SO_NAME).dll.a
LIBRUBY_A = lib$(RUBY_SO_NAME)-static.a
LIBRUBYARG_SHARED = -l$(RUBY_SO_NAME)
LIBRUBYARG_STATIC = -l$(RUBY_SO_NAME)-static $(MAINLIBS)
empty =
OUTFLAG = -o $(empty)
COUTFLAG = -o $(empty)
CSRCFLAG = $(empty)

RUBY_EXTCONF_H = 
cflags   = $(hardenflags)  $(optflags) $(debugflags) $(warnflags)
cxxflags = 
optflags = -O3 -fno-omit-frame-pointer -fno-fast-math
debugflags = -ggdb3
warnflags = -Wall -Wextra -Wdeprecated-declarations -Wdiv-by-zero -Wduplicated-cond -Wimplicit-function-declaration -Wimplicit-int -Wpointer-arith -Wwrite-strings -Wold-style-definition -Wimplicit-fallthrough=0 -Wmissing-noreturn -Wno-cast-function-type -Wno-constant-logical-operand -Wno-long-long -Wno-missing-field-initializers -Wno-overlength-strings -Wno-packed-bitfield-compat -Wno-parentheses-equality -Wno-self-assign -Wno-tautological-compare -Wno-unused-parameter -Wno-unused-value -Wsuggest-attribute=format -Wsuggest-attribute=noreturn -Wunused-variable -Wno-shorten-64-to-32 -Wno-dll-attribute-on-redeclaration -Wmisleading-indentation -Wundef
cppflags = 
CCDLFLAGS = 
CFLAGS   = $(CCDLFLAGS) -O3 -fstack-protector-strong  $(ARCH_FLAG)
INCFLAGS = -I. -I$(arch_hdrdir) -I$(hdrdir)/ruby/backward -I$(hdrdir) -I$(srcdir) -IC:/Ruby40-x64/msys64/ucrt64/bin/../include
DEFS     = -D_FILE_OFFSET_BITS=64
CPPFLAGS = -DHAVE_FFI_H -DRUBY_LIBFFI_MODVERSION=3005002 -DUSE_FFI_CLOSURE_ALLOC=1 -DHAVE_FFI_PREP_CIF_VAR -DHAVE_WINDOWS_H -DHAVE_LOADLIBRARY -DHAVE_FREELIBRARY -DHAVE_GETPROCADDRESS -DHAVE_GETMODULEFILENAME -DSIGNEDNESS_OF_SIZE_T=+1 -DHAVE_RB_STR_TO_INTERNED_STR -D_WIN32_WINNT=0x0600 -D__MINGW_USE_VC2005_COMPAT $(DEFS) $(cppflags)
CXXFLAGS = $(CCDLFLAGS) -Wno-dll-attribute-on-redeclaration  $(ARCH_FLAG)
ldflags  = -L. -pipe -s -fstack-protector-strong -lpthread -Wl,--no-as-needed -LC:/Ruby40-x64/msys64/ucrt64/bin/../lib/../lib
dldflags = -pipe -s -fstack-protector-strong -lpthread -Wl,--enable-auto-image-base,--enable-auto-import $(DEFFILE)
ARCH_FLAG = 
DLDFLAGS = $(ldflags) $(dldflags) $(ARCH_FLAG)
LDSHARED = $(CC) -shared
LDSHAREDXX = $(CXX) -shared
POSTLINK = :
AR = gcc-ar
LD = ld
EXEEXT = .exe

RUBY_INSTALL_NAME = $(RUBY_BASE_NAME)
RUBY_SO_NAME = x64-ucrt-ruby400
RUBYW_INSTALL_NAME = $(RUBYW_BASE_NAME)
RUBY_VERSION_NAME = $(RUBY_BASE_NAME)-$(ruby_version)
RUBYW_BASE_NAME = rubyw
RUBY_BASE_NAME = ruby

arch = x64-mingw-ucrt
sitearch = x64-ucrt
ruby_version = 4.0.0
ruby = $(bindir)/$(RUBY_BASE_NAME)
RUBY = $(ruby)
BUILTRUBY = $(bindir)/$(RUBY_BASE_NAME).exe
ruby_headers = $(hdrdir)/ruby.h $(hdrdir)/ruby/backward.h $(hdrdir)/ruby/ruby.h $(hdrdir)/ruby/defines.h $(hdrdir)/ruby/missing.h $(hdrdir)/ruby/intern.h $(hdrdir)/ruby/st.h $(hdrdir)/ruby/subst.h $(arch_hdrdir)/ruby/config.h

RM = rm -f
RM_RF = rm -fr
RMDIRS = rmdir --ignore-fail-on-non-empty -p
MAKEDIRS = /usr/bin/mkdir -p
INSTALL = /usr/bin/install -c
INSTALL_PROG = $(INSTALL) -m 0755
INSTALL_DATA = $(INSTALL) -m 644
COPY = cp
TOUCH = exit >

#### End of system configuration section. ####

preload = 
libpath = . $(libdir)
LIBPATH = -L. -L$(libdir)
DEFFILE = $(TARGET)-$(arch).def

CLEANFILES = mkmf.log $(DEFFILE)
DISTCLEANFILES = 
DISTCLEANDIRS = 

extout = 
extout_prefix = 
target_prefix = 
LOCAL_LIBS = 
LIBS = $(LIBRUBYARG_SHARED) -lws2_32 -lffi  -lffi -lshell32 -lws2_32 -liphlpapi -limagehlp -lshlwapi -lbcrypt  
ORIG_SRCS = closure.c conversions.c fiddle.c function.c handle.c memory_view.c pinned.c pointer.c
SRCS = $(ORIG_SRCS) 
OBJS = closure.o conversions.o fiddle.o function.o handle.o memory_view.o pinned.o pointer.o
HDRS = $(srcdir)/closure.h $(srcdir)/conversions.h $(srcdir)/fiddle.h $(srcdir)/function.h
LOCAL_HDRS = 
TARGET = fiddle
TARGET_NAME = fiddle
TARGET_ENTRY = Init_$(TARGET_NAME)
DLLIB = $(TARGET).so
EXTSTATIC = 
STATIC_LIB = 

TIMESTAMP_DIR = .
BINDIR        = $(bindir)
RUBYCOMMONDIR = $(sitedir)$(target_prefix)
RUBYLIBDIR    = $(sitelibdir)$(target_prefix)
RUBYARCHDIR   = $(sitearchdir)$(target_prefix)
HDRDIR        = $(sitehdrdir)$(target_prefix)
ARCHHDRDIR    = $(sitearchhdrdir)$(target_prefix)
TARGET_SO_DIR =
TARGET_SO     = $(TARGET_SO_DIR)$(DLLIB)
CLEANLIBS     = $(TARGET_SO)
CLEANOBJS     = $(OBJS) *.bak
TARGET_SO_DIR_TIMESTAMP = $(TIMESTAMP_DIR)/.sitearchdir.time
LIBFFI_CLEAN = none

all:    $(DLLIB)
static: $(STATIC_LIB)
.PHONY: all install static install-so install-rb
.PHONY: clean clean-so clean-static clean-rb

clean-static::
clean-rb-default::
clean-rb::
clean-so::
clean: clean-so clean-static clean-rb-default clean-rb
		-$(Q)$(RM_RF) $(CLEANLIBS) $(CLEANOBJS) $(CLEANFILES) .*.time

distclean-rb-default::
distclean-rb::
distclean-so::
distclean-static::
distclean: clean distclean-so distclean-static distclean-rb-default distclean-rb
		-$(Q)$(RM) Makefile $(RUBY_EXTCONF_H) conftest.* mkmf.log
		-$(Q)$(RM) core ruby$(EXEEXT) *~ $(DISTCLEANFILES)
		-$(Q)$(RMDIRS) $(DISTCLEANDIRS) 2> NUL || true

realclean: distclean
install: install-so install-rb

install-so: $(DLLIB) $(TARGET_SO_DIR_TIMESTAMP)
	$(INSTALL_PROG) $(DLLIB) $(RUBYARCHDIR)
clean-static::
	-$(Q)$(RM) $(STATIC_LIB)
install-rb: pre-install-rb do-install-rb install-rb-default
install-rb-default: pre-install-rb-default do-install-rb-default
pre-install-rb: Makefile
pre-install-rb-default: Makefile
do-install-rb:
do-install-rb-default:
pre-install-rb-default:
	@$(NULLCMD)
$(TARGET_SO_DIR_TIMESTAMP):
	$(Q) $(MAKEDIRS) $(@D) $(RUBYARCHDIR)
	$(Q) $(TOUCH) $@

site-install: site-install-so site-install-rb
site-install-so: install-so
site-install-rb: install-rb

.SUFFIXES: .c .m .cc .mm .cxx .cpp .o .S

.cc.o:
	$(ECHO) compiling $(<)
	$(Q) $(CXX) $(INCFLAGS) $(CPPFLAGS) $(CXXFLAGS) $(COUTFLAG)$@ -c $(CSRCFLAG)$<

.cc.S:
	$(ECHO) translating $(<)
	$(Q) $(CXX) $(INCFLAGS) $(CPPFLAGS) $(CXXFLAGS) $(COUTFLAG)$@ -S $(CSRCFLAG)$<

.mm.o:
	$(ECHO) compiling $(<)
	$(Q) $(CXX) $(INCFLAGS) $(CPPFLAGS) $(CXXFLAGS) $(COUTFLAG)$@ -c $(CSRCFLAG)$<

.mm.S:
	$(ECHO) translating $(<)
	$(Q) $(CXX) $(INCFLAGS) $(CPPFLAGS) $(CXXFLAGS) $(COUTFLAG)$@ -S $(CSRCFLAG)$<

.cxx.o:
	$(ECHO) compiling $(<)
	$(Q) $(CXX) $(INCFLAGS) $(CPPFLAGS) $(CXXFLAGS) $(COUTFLAG)$@ -c $(CSRCFLAG)$<

.cxx.S:
	$(ECHO) translating $(<)
	$(Q) $(CXX) $(INCFLAGS) $(CPPFLAGS) $(CXXFLAGS) $(COUTFLAG)$@ -S $(CSRCFLAG)$<

.cpp.o:
	$(ECHO) compiling $(<)
	$(Q) $(CXX) $(INCFLAGS) $(CPPFLAGS) $(CXXFLAGS) $(COUTFLAG)$@ -c $(CSRCFLAG)$<

.cpp.S:
	$(ECHO) translating $(<)
	$(Q) $(CXX) $(INCFLAGS) $(CPPFLAGS) $(CXXFLAGS) $(COUTFLAG)$@ -S $(CSRCFLAG)$<

.c.o:
	$(ECHO) compiling $(<)
	$(Q) $(CC) $(INCFLAGS) $(CPPFLAGS) $(CFLAGS) $(COUTFLAG)$@ -c $(CSRCFLAG)$<

.c.S:
	$(ECHO) translating $(<)
	$(Q) $(CC) $(INCFLAGS) $(CPPFLAGS) $(CFLAGS) $(COUTFLAG)$@ -S $(CSRCFLAG)$<

.m.o:
	$(ECHO) compiling $(<)
	$(Q) $(CC) $(INCFLAGS) $(CPPFLAGS) $(CFLAGS) $(COUTFLAG)$@ -c $(CSRCFLAG)$<

.m.S:
	$(ECHO) translating $(<)
	$(Q) $(CC) $(INCFLAGS) $(CPPFLAGS) $(CFLAGS) $(COUTFLAG)$@ -S $(CSRCFLAG)$<

$(TARGET_SO): $(DEFFILE) $(OBJS) Makefile
	$(ECHO) linking shared-object $(DLLIB)
	-$(Q)$(RM) $(@)
	$(Q) $(LDSHARED) -o $@ $(OBJS) $(LIBPATH) $(DLDFLAGS) $(LOCAL_LIBS) $(LIBS)
	$(Q) $(POSTLINK)



$(DEFFILE): 
	$(ECHO) generating $(@)
	$(Q) (echo EXPORTS && echo $(TARGET_ENTRY)) > $@

###
PWD =

CONFIGURE_LIBFFI = \
	$(LIBFFI_CONFIGURE) --disable-shared \
		--host=$(LIBFFI_ARCH) --enable-builddir=$(arch) \
		CC="$(CC)" CFLAGS="$(LIBFFI_CFLAGS)" \
		LD="$(LD)" LDFLAGS="$(LIBFFI_LDFLAGS)"

$(STATIC_LIB) $(RUBYARCHDIR)/$(DLLIB) $(DLLIB): $(LIBFFI_A)

$(OBJS): $(FFI_H)

.PHONY: .FORCE hdr

.FORCE:

hdr: $(FFI_H)

configure-libffi build-libffi: .FORCE
configure-libffi \
$(LIBFFI_DIR)/include/ffi.h \
$(LIBFFI_DIR)/include/ffitarget.h \
$(LIBFFI_DIR)/fficonfig.h \
$(LIBFFI_DIR)/Makefile:
	$(Q) $(MAKEDIRS) $(LIBFFI_DIR)
	$(Q) $(CONFIGURE_LIBFFI)

build-libffi $(LIBFFI_A):
	$(Q) $(SUBMAKE_PRE) $(MAKE) $(SUBMAKE_ARG)

clean-none:
clean-libffi:
	$(Q) $(SUBMAKE_PRE) $(MAKE) $(SUBMAKE_ARG) clean

distclean-none:
distclean-libffi:
	$(Q) $(SUBMAKE_PRE) $(MAKE) $(SUBMAKE_ARG) distclean
	$(Q) $(RM) $(LIBFFI_DIR)/local.exp
	$(Q) $(RUBY) -rfileutils -e "FileUtils.rmdir(Dir.glob(ARGV[0]+'/**/{,.*/}'), :parents=>true)" $(LIBFFI_DIR)

realclean-none:
realclean-libffi:
	$(Q) $(RMALL) $(LIBFFI_DIR)

.PHONY: clean-libffi distclean-libffi realclean-libffi
.PHONY: clean-none distclean-none realclean-none

clean: clean-$(LIBFFI_CLEAN)
distclean: distclean-$(LIBFFI_CLEAN)
realclean: realclean-$(LIBFFI_CLEAN)

.PHONY: configure configure-libffi

closure.o: closure.c
closure.o: closure.h
closure.o: conversions.h
closure.o: fiddle.h
closure.o: function.h
conversions.o: closure.h
conversions.o: conversions.c
conversions.o: conversions.h
conversions.o: fiddle.h
conversions.o: function.h
fiddle.o: closure.h
fiddle.o: conversions.h
fiddle.o: fiddle.c
fiddle.o: fiddle.h
fiddle.o: function.h
function.o: closure.h
function.o: conversions.h
function.o: fiddle.h
function.o: function.c
function.o: function.h
handle.o: closure.h
handle.o: conversions.h
handle.o: fiddle.h
handle.o: function.h
handle.o: handle.c
memory_view.o: fiddle.h
memory_view.o: memory_view.c
pointer.o: closure.h
pointer.o: conversions.h
pointer.o: fiddle.h
pointer.o: function.h
pointer.o: pointer.c
