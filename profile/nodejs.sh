export PATH="$HOME/.scalingo/node/bin:$HOME/.scalingo/yarn/bin:$PATH:$HOME/bin:$HOME/node_modules/.bin"
export NODE_HOME="$HOME/.scalingo/node"
export NODE_ENV=${NODE_ENV:-production}
export NODE_EXTRA_CA_CERTS=${NODE_EXTRA_CA_CERTS:-/usr/share/ca-certificates/Scalingo/scalingo-database.pem}
