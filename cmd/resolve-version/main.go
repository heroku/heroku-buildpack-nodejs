package main

import (
	"errors"
	"fmt"
	"regexp"

	"github.com/Masterminds/semver"
)

type release struct {
	binary   string
	stage    string
	platform string
	url      string
	version  *semver.Version
}

// Parses an S3 key into a struct of information about that release
// Example input: node/release/linux-x64/node-v6.2.2-linux-x64.tar.gz
func parseObject(key string) (release, error) {
	nodeRegex := regexp.MustCompile("node\\/([^\\/]+)\\/([^\\/]+)\\/node-v([0-9]+\\.[0-9]+\\.[0-9]+)-([^.]*)(.*)\\.tar\\.gz")
	yarnRegex := regexp.MustCompile("yarn\\/([^\\/]+)\\/yarn-v([0-9]+\\.[0-9]+\\.[0-9]+)\\.tar\\.gz")

	if nodeRegex.MatchString(key) {
		match := nodeRegex.FindStringSubmatch(key)
		version, err := semver.NewVersion(match[3])
		if err != nil {
			return release{}, fmt.Errorf("Failed to parse version as semver:%s\n%s", match[3], err.Error())
		}
		return release{
			binary:   "node",
			stage:    match[1],
			platform: match[2],
			version:  version,
			url:      fmt.Sprintf("https://s3.amazonaws.com/%s/node/%s/%s/node-v%s-%s.tar.gz", "heroku-nodebin", match[1], match[2], match[3], match[2]),
		}, nil
	}

	if yarnRegex.MatchString(key) {
		match := yarnRegex.FindStringSubmatch(key)
		version, err := semver.NewVersion(match[2])
		if err != nil {
			return release{}, errors.New("Failed to parse version as semver")
		}
		return release{
			binary:   "yarn",
			stage:    match[1],
			platform: "",
			url:      fmt.Sprintf("https://s3.amazonaws.com/heroku-nodebin/yarn/release/yarn-v%s.tar.gz", version),
			version:  version,
		}, nil
	}

	return release{}, fmt.Errorf("Failed to parse key: %s", key)
}

func main() {
	fmt.Println("hello world")
}
