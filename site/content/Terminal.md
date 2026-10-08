# Terminal

The Homebrew cask puts a `markview` command on your path.

```sh
markview README.md            # open a file
markview docs                 # open a folder
git log --oneline | markview  # show what is piped in
```

Without Homebrew, link the command yourself:

```sh
ln -s /Applications/Markview.app/Contents/Resources/markview /usr/local/bin/markview
```
