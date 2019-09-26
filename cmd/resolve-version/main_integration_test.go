// +build integration

package main

import (
	"regexp"
	"testing"

	"github.com/stretchr/testify/assert"
)

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
