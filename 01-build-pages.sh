#! /bin/sh
# vim: set noexpandtab tw=0:
# Rebuild the documentation and upload this to the web server.

set -e # we want to fail on any error instead of risking uploading broken stuff
#set -x

curdir=$(pwd)

# Path to po4a sources
srcdir=../po4a

if [ ! -e ${srcdir}/po4a-gettextize ]
then 
	echo "The source tree of po4a does not seem to be in '${srcdir}'."
	echo "Please fix the srcdir variable at the top of this script."
	exit 1
fi

percent_lang() {
	STATS=`msgfmt -o /dev/null --statistics $srcdir/po/pod/$1.po 2>&1`
	YES=`echo $STATS | sed -n -e 's/^\([[:digit:]]*\).*$/\1/p'`
	NO=`echo $STATS | sed -n -e 's/^\([[:digit:]]\+\)[^[:digit:]]\+\([[:digit:]]\+\).*$/\2/p'`
	if [ ! $NO ]; then
		NO=0
	fi
	O3=`echo $STATS | sed -n -e 's/^\([[:digit:]]\+\)[^[:digit:]]\+\([[:digit:]]\+\)[^[:digit:]]\+\([[:digit:]]\+\).*$/\3/p'`
	if [ $O3 ]; then
		NO=$(($NO + $O3))
	fi
	TOTAL=$(($YES+$NO))
	echo $((($YES*100)/$TOTAL))
}

cd $srcdir
LANGS=
for lang in po/pod/*.po
do
	LANGS=$LANGS" "$(echo $lang | sed -e 's,^po/pod/,,' -e 's,\.po$,,')
done

perl Build.PL
PO4AFLAGS='-k 0' ./Build
cd $curdir

rm -rf html/
find src -name \*~ -exec rm {} \;
cp -a $srcdir/blib/man html
#cp -a $srcdir/blib/libdoc html/man3
find html -name \*.gz -exec gunzip {} \;
#find html/man3 html/*/man3 -name \*.3 -exec mv {} {}pm \;
for f in $(find html/man1 html/*/man1 -name \*.1p); do mv $f ${f%p}; done
mkdir -p html/en/
mv html/man* html/en/
mkdir html/man
mkdir html/man/man1
mkdir html/man/man3
mkdir html/man/man5
mkdir html/man/man7

libver=$(grep '$VERSION=' $srcdir/lib/Locale/Po4a/TransTractor.pm | \
         sed -e 's/^.*"\([^"]*\)".*/\1/')

echo "Generate the web pages translations with po4a"
PERLLIB=$srcdir/lib $srcdir/po4a --previous -v --msgid-bugs-address po4a-devel@lists.alioth.debian.org --package-name po4a --package-version $libver po/html.cfg

for lang in po/www/*.po
do
	lang=$(basename ${lang%.po})
	for f in html/*.$lang
	do
		sed -i -e "s/\.en\"; ?>/\.$lang\"; ?>/" $f
	done
done

# Main page
#for lang in $LANGS ; do
#	PERC=`percent_lang $lang`
#	echo "   $lang ($PERC% translated):
#   <a href=\"$lang/man7/po4a.7.php\">Introduction</a>
#   <a href=\"$lang/\">Index</a>
#   <br>" >> html/documentation_translations.php
#done
#echo "   <br>
#   Last update: `LANG=C date`" >> html/documentation_translations.php

for lang in en $LANGS ; do
	header=header.php.$lang
	[ -e html/$header ] || header=header.php.en
	echo Generate the $lang index

	cat << EOT > html/man/index.php.$lang
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">
<html>
 <head>
  <link rel="stylesheet"
        title="Default Style"
        type="text/css"
        href="../default.css" >
  <meta content="text/html; charset=UTF-8" http-equiv="Content-Type">
  <title>Table of Contents</title>
 </head>
 <body>
  <?php \$topdir = "../"; include "../$header"; ?>
  <div id="content">
  <h1>Table of Contents</h1>
   <table>
EOT
	for man in html/en/man*/*
	do
		man=${man#html/en/}
		if test -e html/$lang/$man
		then
			page=html/$lang/$man
		else
			page=html/en/$man
		fi
		title=$(lexgrog "$page" |
		        sed -ne 's/.*: \".* - //;s/"$//;p')
		ref=$man.php
		man=$(basename $man)
		man=$(echo $man | sed -e 's/^\(.*\)\.\([0-9]\(pm\)\?\)$/\1(\2)/')
		cat << EOT >> html/man/index.php.$lang
    <tr>
     <td><a href="$ref">$man</a></td>
     <td>$title</td>
    </tr>
EOT
	done
	cat << EOT >> html/man/index.php.$lang
   </table>
  </div>
  <?php include "footer_index.php"; ?>
  <?php include "../footer.php"; ?>
 </body>
</html>
EOT

	echo Generate the $lang HTML pages
	for man in html/$lang/man*/*
	do
		#test -e $man || continue
		out=html/man/${man#html/$lang/}.php.$lang
		footer=footer_$(basename $out)
		footer=${footer%.$lang}
		man2html -r $man | sed -e '/Content-type: text.html/d' \
		                       -e '/cgi-bin.man.man2html/d' \
		                       -e 's/\.html"/\.php"/g' \
		                       -e 's,/man3pm/,/man3/,g' \
		                       -e 's,<HEAD>,<HEAD><link rel="stylesheet" title="Default Style" type="text/css" href="../../default.css"><meta content="text/html; charset=UTF-8" http-equiv="Content-Type">,' \
		                       -e 's,<BODY>,<BODY><?php $topdir = "../../"; include "../../'$header'"; ?><div id="content">,' \
		                       -e 's,</BODY>,</div><?php include "'$footer'"; ?><?php include "../../footer.php"; ?></BODY>,' > $out
	done

	if [ "$lang" != "en" ]
	then
		rm -rf html/$lang
	fi
done
rm -rf html/en

gen_translations() {
	dir="$1"

	total=$(LC_ALL=C msgfmt -o /dev/null --statistics "$dir"/*.pot 2>&1 | \
	        sed -ne "s/^.* \([0-9]*\) untranslated.*$/\1/p;d")

	echo "<table>"
	for pofile in "$dir"/*.po
	do
		lang=${pofile%.po}
		lang=$(basename $lang)
		stats=$(LC_ALL=C msgfmt -o /dev/null --statistics $pofile 2>&1)
		echo -n "<tr><td>$lang</td><td>"
		for type in translated fuzzy untranslated
		do
			strings=$(echo " $stats" | \
			          sed -ne "s/^.* \([0-9]*\) $type.*$/\1/p;d")
			if [ -n "$strings" ]
			then
				pcent=$((strings*100/total))
				width=$((strings*200/total))
				echo -n "<img height=\"10\" src=\"$type.png\" "
				echo -n "style=\"height: 1em;\" "
				echo -n "width=\"$width\" "
				echo -n "alt=\"$pcent% $type ($strings/$total), \" "
				echo -n "title=\"$type: $pcent% ($strings/$total)\"/>"
			fi
		done
		echo "</td></tr>"
	done
	echo "<?php include \"table_translations_legend.php\";?>"
	echo "</table>"
	echo "<p>Last update: `LC_ALL=C date`.</p>"
}

echo Generate the translation statistics for po/bin
gen_translations $srcdir/po/bin > html/table_translations_bin.php
echo Generate the translation statistics for po/pod
gen_translations $srcdir/po/pod > html/table_translations_pod.php
echo Generate the translation statistics for po/www
gen_translations po/www > html/table_translations_www.php

echo Extract the version
echo $libver > html/version.php

get_language() {
# FIXME: use gettext
	case $1 in
		ca)
			echo -n "català"
			;;
		de)
			echo -n "Deutsch"
			;;
		en)
			echo -n "English"
			;;
		es)
			echo -n "español"
			;;
		fr)
			echo -n "français"
			;;
		it)
			echo -n "Italiano"
			;;
		pl)
			echo -n "polski"
			;;
		pt)
			echo -n "Português"
			;;
		pt_BR)
			echo -n "Português (Brasil)"
			;;
		ja)
			echo -n "日本語"
			;;
		ru)
			echo -n "Русский"
			;;
		zh_CN)
			echo -n "简体中文"
			;;
		*)
			echo "Language '$1' not supported" >&2
			exit 1
			;;
	esac
}

gen_language_footer() {
	page="$1"
	page=${page%.en}
	page=${page#src/}
	page=${page#html/}
	out=html/$(dirname $page)/footer_$(basename $page)
#	echo "Generating language footer for $page in $out"
	echo "<div id=\"languages\">" > $out
	for langcode in $(ls src/$page.* html/$page.* 2>/dev/null |grep -v *~)
	do
		echo $langcode
		langcode=${langcode#src/$page.}
		langcode=${langcode#html/$page.}
		language=$(get_language $langcode)
		echo "<a href=\"$(basename $page | sed -e 's/:/%3A/g').$langcode\">$language</a>" >> $out
	done
	echo "</div>" >> $out
#	echo "done"
}

echo "Generating language footers"
for page in src/*.en
do
	gen_language_footer "$page"
done

find html -name "*.en" |
while read page
do
	gen_language_footer "$page"
done

echo "The pages are built now. You can browse them in html/, or upload them"
