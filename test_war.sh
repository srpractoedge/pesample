 grails -Dgeb.env=firefox test-app functional:cucumber --non-interactive --stacktrace
 echo "successfully tested, continuing with war"
 grailsw war