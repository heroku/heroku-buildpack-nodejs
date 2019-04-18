package main

import (
	"testing"

	"github.com/Masterminds/semver"

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

func genReleasesFromArray(versions []string) []release {
	out := []release{}
	for _, version := range versions {
		out = append(out, release{
			binary:   "node",
			stage:    "release",
			platform: "linux-x64",
			url:      "https://heroku.com",
			version:  semver.MustParse(version),
		})
	}
	return out
}

func TestMatchReleaseExact(t *testing.T) {
	releases := genReleasesFromArray([]string{"1.0.0", "1.0.1", "1.0.2"})

	release, err := matchReleaseExact(releases, "1.0.1")
	assert.Nil(t, err)
	assert.Equal(t, release.version.String(), "1.0.1")

	release, err = matchReleaseExact(releases, "1.0.2")
	assert.Nil(t, err)
	assert.Equal(t, release.version.String(), "1.0.2")

	release, err = matchReleaseExact(releases, "1.0.3")
	assert.Error(t, err)
	assert.Equal(t, err.Error(), "No matching version for: 1.0.3")
}
