package main

import (
	"regexp"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestParseObject(t *testing.T) {
	release, err := parseObject("node/release/linux-x64/node-v6.2.2-linux-x64.tar.gz")
	assert.Nil(t, err)
	assert.Equal(t, release.binary, "node")
	assert.Equal(t, release.stage, "release")
	assert.Equal(t, release.platform, "linux-x64")
	assert.Equal(t, release.version.String(), "6.2.2")

	release, err = parseObject("node/release/darwin-x64/node-v8.14.1-darwin-x64.tar.gz")
	assert.Nil(t, err)
	assert.Equal(t, release.binary, "node")
	assert.Equal(t, release.stage, "release")
	assert.Equal(t, release.platform, "darwin-x64")
	assert.Equal(t, release.version.String(), "8.14.1")

	release, err = parseObject("node/staging/darwin-x64/node-v6.17.0-darwin-x64.tar.gz")
	assert.Nil(t, err)
	assert.Equal(t, release.binary, "node")
	assert.Equal(t, release.stage, "staging")
	assert.Equal(t, release.platform, "darwin-x64")
	assert.Equal(t, release.version.String(), "6.17.0")

	release, err = parseObject("yarn/release/yarn-v1.9.1.tar.gz")
	assert.Nil(t, err)
	assert.Equal(t, release.binary, "yarn")
	assert.Equal(t, release.stage, "release")
	assert.Equal(t, release.platform, "")
	assert.Equal(t, release.version.String(), "1.9.1")

	release, err = parseObject("something/weird")
	assert.NotNil(t, err)
	assert.Equal(t, err.Error(), "Failed to parse key: something/weird")
}

func TestListS3Objects(t *testing.T) {
	// Node
	objects, err := listS3Objects("heroku-nodebin", "node")
	assert.Nil(t, err)
	assert.NotEmpty(t, objects)

	// every returned result started with "node"
	for _, obj := range objects {
		assert.Regexp(t, regexp.MustCompile("^node"), obj.Key)
	}

	// every node object must parse as a valid release
	for _, obj := range objects {
		release, err := parseObject(obj.Key)
		assert.Nil(t, err)
		assert.Regexp(t, regexp.MustCompile("https:\\/\\/s3.amazonaws.com\\/heroku-nodebin"), release.url)
		assert.Regexp(t, regexp.MustCompile("[0-9]+.[0-9]+.[0-9]+"), release.version.String())
	}

	// Yarn
	objects, err = listS3Objects("heroku-nodebin", "yarn")
	assert.Nil(t, err)
	assert.NotEmpty(t, objects)

	// every returned result started with "yarn"
	for _, obj := range objects {
		assert.Regexp(t, regexp.MustCompile("^yarn"), obj.Key)
	}

	// every yarn object must parse as a valid release
	for _, obj := range objects {
		release, err := parseObject(obj.Key)
		assert.Nil(t, err)
		assert.Regexp(t, regexp.MustCompile("https:\\/\\/s3.amazonaws.com\\/heroku-nodebin"), release.url)
		assert.Regexp(t, regexp.MustCompile("[0-9]+.[0-9]+.[0-9]+"), release.version.String())
	}
}
