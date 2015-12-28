# Import DokuWiki into Evernote

This is a set of scripts to port DokuWiki into Evernote.
They are not "ready-to-use" without tweaking them for your requirements but a friend of mine suggested to publish them anyways so someone else might not have to start from scratch.

How to use them:
- Step 0: Get yourself registered as an Evernote APP and set OAUTH_CONSUMER_KEY and OAUTH_CONSUMER_SECRET environment variables
- Step 1: Download you DokuWiki content and put them into /data
- Step 2: Checkout the DokuWiki sourcecode and put it into /dokuwiki
- Step 3: Use ./export.php to create HTML Pages from the DokuWiki pages
- Step 4: Use get_evernote_oauth.rb to get the oauth key and set the OAUTH_AUTH_TOKEN environment variable
- Step 5: Customize the push_to_evernote.rb to your needs
- Step 6: Use push_to_evernote.rb to push your content to evernote

If you have questions, feel free to ask.

