package main

import (
	"encoding/xml"
	"errors"
	"fmt"
	"io/ioutil"
	"net/http"
	"net/url"
	"regexp"
	"time"

	"github.com/Masterminds/semver"
)

type result struct {
	Name                  string     `xml:"Name"`
	KeyCount              int        `xml:"KeyCount"`
	MaxKeys               int        `xml:"MaxKeys"`
	IsTruncated           bool       `xml:"IsTruncated"`
	ContinuationToken     string     `xml:"ContinuationToken"`
	NextContinuationToken string     `xml:"NextContinuationToken"`
	Prefix                string     `xml:"Prefix"`
	Contents              []s3Object `xml:"Contents"`
}

type s3Object struct {
	Key          string    `xml:"Key"`
	LastModified time.Time `xml:"LastModified"`
	ETag         string    `xml:"ETag"`
	Size         int       `xml:"Size"`
	StorageClass string    `xml:"StorageClass"`
}

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

// Wrapper around the S3 API for listing objects
// This maps directly to the API and parses the XML response but will not handle
// paging and offsets automaticaly
func fetchS3Result(bucketName string, options map[string]string) (result, error) {
	var result result
	v := url.Values{}
	v.Set("list-type", "2")
	for key, val := range options {
		v.Set(key, val)
	}
	url := fmt.Sprintf("https://%s.s3.amazonaws.com?%s", bucketName, v.Encode())
	resp, err := http.Get(url)
	if err != nil {
		return result, err
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return result, err
	}

	return result, xml.Unmarshal(body, &result)
}

// Query the S3 API for a list of all the objects in an S3 bucket with a
// given prefix. This will handle the inherent 1000 item limit and paging
// for you
func listS3Objects(bucketName string, prefix string) ([]s3Object, error) {
	var out = []s3Object{}
	var options = map[string]string{"prefix": prefix}

	for {
		result, err := fetchS3Result(bucketName, options)
		if err != nil {
			return nil, err
		}

		out = append(out, result.Contents...)
		if !result.IsTruncated {
			break
		}

		options["continuation-token"] = result.NextContinuationToken
	}

	return out, nil
}

func main() {
	fmt.Println("hello world")
}
