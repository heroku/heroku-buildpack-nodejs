package main

import (
	"fmt"
	"testing"
	"time"

	"github.com/jmorrell/semver"

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

	result := matchReleaseExact(releases, "1.0.1")
	assert.True(t, result.matched)
	assert.Equal(t, result.release.version.String(), "1.0.1")

	result = matchReleaseExact(releases, "1.0.2")
	assert.True(t, result.matched)
	assert.Equal(t, result.release.version.String(), "1.0.2")

	result = matchReleaseExact(releases, "1.0.3")
	assert.False(t, result.matched)
	assert.Equal(t, result.versionRequirement, "1.0.3")
}

type Case struct {
	input  string
	output string
}

func TestMatchReleaseSemver(t *testing.T) {
	// The current supported releases as of 9/16/2019
	releases := genReleasesFromArray([]string{
		"10.0.0", "10.1.0", "10.10.0", "10.11.0", "10.12.0", "10.13.0", "10.14.0", "10.14.1", "10.14.2", "10.15.0",
		"10.15.1", "10.15.2", "10.15.3", "10.2.0", "10.2.1", "10.3.0", "10.4.0", "10.4.1", "10.5.0", "10.6.0",
		"10.7.0", "10.8.0", "10.9.0", "11.0.0", "11.1.0", "11.10.0", "11.10.1", "11.11.0", "11.12.0", "11.13.0",
		"11.14.0", "11.2.0", "11.3.0", "11.4.0", "11.5.0", "11.6.0", "11.7.0", "11.8.0", "11.9.0", "6.0.0",
		"6.1.0", "6.10.0", "6.10.1", "6.10.2", "6.10.3", "6.11.0", "6.11.1", "6.11.2", "6.11.3", "6.11.4",
		"6.11.5", "6.12.0", "6.12.1", "6.12.2", "6.12.3", "6.13.0", "6.13.1", "6.14.0", "6.14.1", "6.14.2",
		"6.14.3", "6.14.4", "6.15.0", "6.15.1", "6.16.0", "6.17.0", "6.17.1", "6.2.0", "6.2.1", "6.2.2",
		"6.3.0", "6.3.1", "6.4.0", "6.5.0", "6.6.0", "6.7.0", "6.8.0", "6.8.1", "6.9.0", "6.9.1", "6.9.2",
		"6.9.3", "6.9.4", "6.9.5", "8.0.0", "8.1.0", "8.1.1", "8.1.2", "8.1.3", "8.1.4", "8.10.0", "8.11.0",
		"8.11.1", "8.11.2", "8.11.3", "8.11.4", "8.12.0", "8.13.0", "8.14.0", "8.14.1", "8.15.0", "8.15.1",
		"8.16.0", "8.2.0", "8.2.1", "8.3.0", "8.4.0", "8.5.0", "8.6.0", "8.7.0", "8.8.0", "8.8.1", "8.9.0",
		"8.9.1", "8.9.2", "8.9.3", "8.9.4",
	})

	// Semver requirements pulled from real apps
	cases := []Case{
		Case{input: "10.x", output: "10.15.3"},
		Case{input: "10.*", output: "10.15.3"},
		Case{input: "10", output: "10.15.3"},
		Case{input: "8.x", output: "8.16.0"},
		Case{input: "^8.11.3", output: "8.16.0"},
		Case{input: "~8.11.3", output: "8.11.4"},
		Case{input: ">= 6.0.0", output: "11.14.0"},
		Case{input: "^6.9.0 || ^8.9.0 || ^10.13.0", output: "10.15.3"},
		Case{input: "6.* || 8.* || >= 10.*", output: "11.14.0"},
		Case{input: ">= 6.11.1 <= 10", output: "10.15.3"},
		Case{input: ">=8.10 <11", output: "10.15.3"},
		Case{input: "v10.15.3", output: "10.15.3"},
	}

	for _, c := range cases {
		result, err := matchReleaseSemver(releases, c.input)
		assert.Nil(t, err)
		assert.True(t, result.matched)
		assert.Equal(t, result.release.version.String(), c.output)
	}

	result, err := matchReleaseSemver(releases, "99.x")
	assert.Nil(t, err)
	assert.False(t, result.matched)
	assert.Equal(t, result.versionRequirement, "99.x")
}

func genYarnS3ObjectList(versions []string) []s3Object {
	out := []s3Object{}
	for _, version := range versions {
		out = append(out, s3Object{
			Key:          fmt.Sprintf("yarn/release/yarn-v%s.tar.gz", version),
			LastModified: time.Time{},
			ETag:         "abcdef",
			Size:         0,
			StorageClass: "normal",
		})
	}
	return out
}

func TestResolveYarn(t *testing.T) {
	// yarn releases as of 4/18/2019
	objects := genYarnS3ObjectList([]string{
		"0.16.0", "0.16.1", "0.17.0", "0.17.10", "0.17.2", "0.17.3", "0.17.4", "0.17.5", "0.17.6",
		"0.17.7", "0.17.8", "0.17.9", "0.18.0", "0.18.1", "0.18.2", "0.19.0", "0.19.1", "0.20.0",
		"0.20.3", "0.20.4", "0.21.0", "0.21.1", "0.21.2", "0.21.3", "0.22.0", "0.23.0", "0.23.2",
		"0.23.3", "0.23.4", "0.24.0", "0.24.1", "0.24.2", "0.24.3", "0.24.4", "0.24.5", "0.24.6",
		"0.25.1", "0.25.2", "0.25.3", "0.25.4", "0.26.1", "0.27.0", "0.27.1", "0.27.2", "0.27.3",
		"0.27.4", "0.27.5", "0.28.1", "0.28.4", "1.0.0", "1.0.1", "1.0.2", "1.1.0", "1.10.0",
		"1.10.1", "1.11.0", "1.11.1", "1.12.0", "1.12.1", "1.12.3", "1.13.0", "1.14.0", "1.15.0",
		"1.15.1", "1.15.2", "1.2.0", "1.2.1", "1.3.2", "1.4.0", "1.5.1", "1.6.0", "1.7.0", "1.8.0",
		"1.9.1", "1.9.2", "1.9.4",
	})

	cases := []Case{
		Case{input: "1.13.0", output: "1.13.0"},
		Case{input: "1.15.2", output: "1.15.2"},
		Case{input: "1.x", output: "1.15.2"},
		Case{input: "*", output: "1.15.2"},
		Case{input: "^1.12.1", output: "1.15.2"},
		Case{input: "^1.9.4", output: "1.15.2"},
		Case{input: ">= 1.0.0", output: "1.15.2"},
		Case{input: "^1.0", output: "1.15.2"},
		Case{input: "0.24.6 - 1.x", output: "1.15.2"},
		Case{input: "1.*.*", output: "1.15.2"},
		Case{input: "^v1.0.1", output: "1.15.2"},
		Case{input: "1.13 - 1.16", output: "1.15.2"},
		Case{input: ">=1.9.4 <2.0.0", output: "1.15.2"},
		// Caret requirements work like ~ when the major is < 1
		Case{input: "^0.27.5", output: "0.27.5"},
		Case{input: "^0.27.2", output: "0.27.5"},
	}

	for _, c := range cases {
		result, err := resolveYarn(objects, c.input)
		if assert.Nil(t, err) {
			assert.True(t, result.matched)
			assert.Equal(t, result.release.version.String(), c.output)
			assert.Equal(t, result.release.url, fmt.Sprintf("https://s3.amazonaws.com/heroku-nodebin/yarn/release/yarn-v%s.tar.gz", c.output))
		}
	}
}

func genNodeS3ObjectList(releaseVersions []string, stagingVersions []string, platform string) []s3Object {
	out := []s3Object{}
	for _, version := range releaseVersions {
		out = append(out, s3Object{
			Key:          fmt.Sprintf("node/release/%s/node-v%s-%s.tar.gz", platform, version, platform),
			LastModified: time.Time{},
			ETag:         "abcdef",
			Size:         0,
			StorageClass: "normal",
		})
	}
	for _, version := range stagingVersions {
		out = append(out, s3Object{
			Key:          fmt.Sprintf("node/staging/%s/node-v%s-%s.tar.gz", platform, version, platform),
			LastModified: time.Time{},
			ETag:         "abcdef",
			Size:         0,
			StorageClass: "normal",
		})
	}
	return out
}

func TestResolveNode(t *testing.T) {
	releasedVersions := []string{
		"10.0.0", "10.1.0", "10.10.0", "10.11.0", "10.12.0", "10.13.0", "10.14.0", "10.14.1", "10.14.2", "10.15.0",
		"10.15.1", "10.15.2", "10.15.3", "10.2.0", "10.2.1", "10.3.0", "10.4.0", "10.4.1", "10.5.0", "10.6.0",
		"10.7.0", "10.8.0", "10.9.0", "11.0.0", "11.1.0", "11.10.0", "11.10.1", "11.11.0", "11.12.0", "11.13.0",
		"11.14.0", "11.2.0", "11.3.0", "11.4.0", "11.5.0", "11.6.0", "11.7.0", "11.8.0", "11.9.0", "6.0.0",
		"6.1.0", "6.10.0", "6.10.1", "6.10.2", "6.10.3", "6.11.0", "6.11.1", "6.11.2", "6.11.3", "6.11.4",
		"6.11.5", "6.12.0", "6.12.1", "6.12.2", "6.12.3", "6.13.0", "6.13.1", "6.14.0", "6.14.1", "6.14.2",
		"6.14.3", "6.14.4", "6.15.0", "6.15.1", "6.16.0", "6.17.0", "6.17.1", "6.2.0", "6.2.1", "6.2.2",
		"6.3.0", "6.3.1", "6.4.0", "6.5.0", "6.6.0", "6.7.0", "6.8.0", "6.8.1", "6.9.0", "6.9.1", "6.9.2",
		"6.9.3", "6.9.4", "6.9.5", "8.0.0", "8.1.0", "8.1.1", "8.1.2", "8.1.3", "8.1.4", "8.10.0", "8.11.0",
		"8.11.1", "8.11.2", "8.11.3", "8.11.4", "8.12.0", "8.13.0", "8.14.0", "8.14.1", "8.15.0", "8.15.1",
		"8.16.0", "8.2.0", "8.2.1", "8.3.0", "8.4.0", "8.5.0", "8.6.0", "8.7.0", "8.8.0", "8.8.1", "8.9.0",
		"8.9.1", "8.9.2", "8.9.3", "8.9.4",
	}

	objects := genNodeS3ObjectList(releasedVersions, []string{}, "linux-x64")

	// Semver requirements pulled from real apps
	cases := []Case{
		Case{input: "10.x", output: "10.15.3"},
		Case{input: "10.*", output: "10.15.3"},
		Case{input: "10", output: "10.15.3"},
		Case{input: "8.x", output: "8.16.0"},
		Case{input: "^8.11.3", output: "8.16.0"},
		Case{input: "~8.11.3", output: "8.11.4"},
		Case{input: ">= 6.0.0", output: "11.14.0"},
		Case{input: "^6.9.0 || ^8.9.0 || ^10.13.0", output: "10.15.3"},
		Case{input: "6.* || 8.* || >= 10.*", output: "11.14.0"},
		Case{input: ">= 6.11.1 <= 10", output: "10.15.3"},
		Case{input: ">=8.10 <11", output: "10.15.3"},
		Case{input: "8 - 10", output: "10.15.3"},
	}

	for _, c := range cases {
		result, err := resolveNode(objects, "linux-x64", c.input)
		if assert.Nil(t, err) {
			assert.True(t, result.matched)
			assert.Equal(t, result.release.version.String(), c.output)
		}
	}

	for _, c := range cases {
		result, err := resolveNode(objects, "darwin-x64", c.input)
		if assert.Nil(t, err) {
			assert.False(t, result.matched)
			assert.Equal(t, result.versionRequirement, c.input)
		}
	}
}

func TestResolveNodeStaging(t *testing.T) {
	releasedVersions := []string{
		"10.0.0", "10.1.0", "10.10.0", "10.11.0", "10.12.0", "10.13.0", "10.14.0", "10.14.1", "10.14.2", "10.15.0",
		"10.15.1", "10.15.2", "10.15.3", "10.2.0", "10.2.1", "10.3.0", "10.4.0", "10.4.1", "10.5.0", "10.6.0",
		"10.7.0", "10.8.0", "10.9.0", "11.0.0", "11.1.0", "11.10.0", "11.10.1", "11.11.0", "11.12.0", "11.13.0",
		"11.14.0", "11.2.0", "11.3.0", "11.4.0", "11.5.0", "11.6.0", "11.7.0", "11.8.0", "11.9.0", "6.0.0",
		"6.1.0", "6.10.0", "6.10.1", "6.10.2", "6.10.3", "6.11.0", "6.11.1", "6.11.2", "6.11.3", "6.11.4",
		"6.11.5", "6.12.0", "6.12.1", "6.12.2", "6.12.3", "6.13.0", "6.13.1", "6.14.0", "6.14.1", "6.14.2",
		"6.14.3", "6.14.4", "6.15.0", "6.15.1", "6.16.0", "6.17.0", "6.17.1", "6.2.0", "6.2.1", "6.2.2",
		"6.3.0", "6.3.1", "6.4.0", "6.5.0", "6.6.0", "6.7.0", "6.8.0", "6.8.1", "6.9.0", "6.9.1", "6.9.2",
		"6.9.3", "6.9.4", "6.9.5", "8.0.0", "8.1.0", "8.1.1", "8.1.2", "8.1.3", "8.1.4", "8.10.0", "8.11.0",
		"8.11.1", "8.11.2", "8.11.3", "8.11.4", "8.12.0", "8.13.0", "8.14.0", "8.14.1", "8.15.0", "8.15.1",
		"8.16.0", "8.2.0", "8.2.1", "8.3.0", "8.4.0", "8.5.0", "8.6.0", "8.7.0", "8.8.0", "8.8.1", "8.9.0",
		"8.9.1", "8.9.2", "8.9.3", "8.9.4",
	}

	platforms := []string{"linux-x64", "darwin-x64"}

	for _, platform := range platforms {
		// staging has a few releases that were already released, but one: 10.15.4 that has not been
		objects := genNodeS3ObjectList(releasedVersions, []string{"10.15.1", "10.15.2", "10.15.3", "10.15.4"}, platform)

		result, err := resolveNode(objects, platform, "10.15.1")
		if assert.Nil(t, err) {
			assert.True(t, result.matched)
			assert.Equal(t, result.release.version.String(), "10.15.1")
			assert.Equal(t, result.versionRequirement, "10.15.1")
			if platform == "linux-x64" {
				assert.Equal(t, result.release.url, "https://s3.amazonaws.com/heroku-nodebin/node/release/linux-x64/node-v10.15.1-linux-x64.tar.gz")
			} else {
				assert.Equal(t, result.release.url, "https://s3.amazonaws.com/heroku-nodebin/node/release/darwin-x64/node-v10.15.1-darwin-x64.tar.gz")
			}
		}

		result, err = resolveNode(objects, platform, "10.15.4")
		if assert.Nil(t, err) {
			assert.True(t, result.matched)
			assert.Equal(t, result.release.version.String(), "10.15.4")
			assert.Equal(t, result.versionRequirement, "10.15.4")
			if platform == "linux-x64" {
				assert.Equal(t, result.release.url, "https://s3.amazonaws.com/heroku-nodebin/node/staging/linux-x64/node-v10.15.4-linux-x64.tar.gz")
			} else {
				assert.Equal(t, result.release.url, "https://s3.amazonaws.com/heroku-nodebin/node/staging/darwin-x64/node-v10.15.4-darwin-x64.tar.gz")
			}
		}

		result, err = resolveNode(objects, platform, "10.15.5")
		if assert.Nil(t, err) {
			assert.False(t, result.matched)
			assert.Equal(t, result.versionRequirement, "10.15.5")
		}
	}
}
