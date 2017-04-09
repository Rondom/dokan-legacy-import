# Makefile for dokan-dev conversion using reposurgeon
#
# Steps to using this:
# 1. Make sure reposurgeon and repotool are on your $PATH.
# 2. For svn, set REMOTE_URL to point at the remote repository
#    you want to convert.
# 3. For cvs, set CVS_HOST to the repo hostname and CVS_MODULE to the module,
#    then uncomment the line that builds REMOTE_URL 
#    Note: for CVS hosts other than Sourceforge or Savannah you will need to 
#    include the path to the CVS modules directory after the hostname.
# 4. Set any required read options, such as --user-ignores or --nobranch,
#    by setting READ_OPTIONS.
# 5. Run 'make stubmap' to create a stub author map.
# 6. (Optional) set REPOSURGEON to point at a faster cython build of the tool.
# 7. Run 'make' to build a converted repository.
#
# The reason both first- and second-stage stream files are generated is that,
# especially with Subversion, making the first-stage stream file is often
# painfully slow. By splitting the process, we lower the overhead of
# experiments with the lift script.
#
# For a production-quality conversion you will need to edit the map
# file and the lift script.  During the process you can set EXTRAS to
# name extra metadata such as a comments mailbox.
#
# Afterwards, you can use the headcompare and tagscompare productions
# to check your work.
#

EXTRAS = 
READ_OPTIONS =
DOKANY_GIT_URL=git@github.com:Rondom/dokany.git
DOKANY_GIT_REPLACE_COMMIT=192b852ed1ac58c448a884311f1ab8b671411e26
DOKANY_TAGS_TO_MIGRATE=0.3.7.1181 0.3.9.1191 0.4.0.1223 0.4.1.1236 0.5.0 0.5.1 0.5.2 0.5.3 0.6.0
VERBOSITY = "verbose 1"
REPOSURGEON = reposurgeon

# Configuration ends here

.PHONY: local-clobber remote-clobber gitk gc compare clean dist stubmap
# Tell make not to auto-remove tag directories, because it only tries rm 
# and hence fails
.PRECIOUS: dokan-dev-%-checkout dokan-dev-%-git

default: dokan-dev-git

connect_with_dokany_git: dokan-dev-git-connected

%-connected: dokan-dev-git
	./connect_with_dokany_git $* $(DOKANY_GIT_URL) $(DOKANY_GIT_REPLACE_COMMIT) "$(DOKANY_TAGS_TO_MIGRATE)"

push_to_dokany_git: dokan-dev-git-connected
	./push_to_dokany_git dokan-dev-git-connected $(DOKANY_GIT_REPLACE_COMMIT) "$(DOKANY_TAGS_TO_MIGRATE)"

# Build the converted repo from the second-stage fast-import stream
dokan-dev-git: dokan-dev.fi
	rm -fr dokan-dev-git; $(REPOSURGEON) "read <dokan-dev.fi" "prefer git" "rebuild dokan-dev-git"

# Build the second-stage fast-import stream from the first-stage stream dump
dokan-dev.fi: dokan-dev.svn dokan-dev.opts dokan-dev.lift dokan-dev.map $(EXTRAS)
	$(REPOSURGEON) $(VERBOSITY) "script dokan-dev.opts" "read $(READ_OPTIONS) <dokan-dev.svn" "authors read <dokan-dev.map" "sourcetype svn" "prefer git" "script dokan-dev.lift" "legacy write >dokan-dev.fo" "write >dokan-dev.fi"

# Google Code Archive already provides a gzipped dump, so we download it
dokan-dev.svn:
	wget https://storage.googleapis.com/google-code-archive-source/v2/code.google.com/dokan/repo.svndump.gz -O - | zcat > dokan-dev.svn

# Instead of using repotool mirror, we simply import the dump we downloaded
dokan-dev-mirror: dokan-dev.svn
	rm -fr dokan-dev-mirror
	svnadmin create dokan-dev-mirror
	svnadmin load dokan-dev-mirror < dokan-dev.svn

# Make a local checkout of the source mirror for inspection
dokan-dev-checkout: dokan-dev-mirror
	cd dokan-dev-mirror >/dev/null; repotool checkout ../dokan-dev-checkout

# Make a local checkout of the source mirror for inspection at a specific tag
dokan-dev-%-checkout: dokan-dev-mirror
	cd dokan-dev-mirror >/dev/null; repotool checkout ../dokan-dev-$*-checkout $*

# Force rebuild of first-stage stream from the local mirror on the next make
local-clobber: clean
	rm -fr dokan-dev.fi dokan-dev-git *~ .rs* dokan-dev-conversion.tar.gz dokan-dev-*-git

# Force full rebuild from the remote repo on the next make.
remote-clobber: local-clobber
	rm -fr dokan-dev.svn dokan-dev-mirror dokan-dev-checkout dokan-dev-*-checkout

# Get the (empty) state of the author mapping from the first-stage stream
stubmap: dokan-dev.svn
	$(REPOSURGEON) "read $(READ_OPTIONS) <dokan-dev.svn" "authors write >dokan-dev.map"

# Compare the histories of the unconverted and converted repositories at head
# and all tags.
EXCLUDE = -x CVS -x .svn -x .git
EXCLUDE += -x .svnignore -x .gitignore
headcompare: dokan-dev-mirror dokan-dev-git
	repotool compare $(EXCLUDE) dokan-dev-mirror dokan-dev-git
tagscompare: dokan-dev-mirror dokan-dev-git
	repotool compare-tags $(EXCLUDE) dokan-dev-mirror dokan-dev-git
branchescompare: dokan-dev-mirror dokan-dev-git
	repotool compare-branches $(EXCLUDE) dokan-dev-mirror dokan-dev-git
allcompare: dokan-dev-mirror dokan-dev-git
	repotool compare-all $(EXCLUDE) dokan-dev-mirror dokan-dev-git

# General cleanup and utility
clean:
	rm -fr *~ .rs* dokan-dev-conversion.tar.gz *.svn *.fi *.fo

# Bundle up the conversion metadata for shipping
SOURCES = Makefile dokan-dev.lift dokan-dev.map $(EXTRAS)
dokan-dev-conversion.tar.gz: $(SOURCES)
	tar --dereference --transform 's:^:dokan-dev-conversion/:' -czvf dokan-dev-conversion.tar.gz $(SOURCES)

dist: dokan-dev-conversion.tar.gz

#
# The following productions are git-specific
#

# Browse the generated git repository
gitk: dokan-dev-git
	cd dokan-dev-git; gitk --all

# Run a garbage-collect on the generated git repository.  Import doesn't.
# This repack call is the active part of gc --aggressive.  This call is
# tuned for very large repositories.
gc: dokan-dev-git
	cd dokan-dev-git; time git -c pack.threads=1 repack -AdF --window=1250 --depth=250
