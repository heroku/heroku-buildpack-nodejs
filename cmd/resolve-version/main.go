package main

import (
	"encoding/xml"
	"errors"
	"fmt"
	"io/ioutil"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"runtime"
	"sort"
	"time"

	"github.com/jmorrell/semver"
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
	version  semver.Version
}

type matchResult struct {
	versionRequirement string
	release            release
	matched            bool
}

func main() {
	if len(os.Args) < 3 {
		printUsage()
		os.Exit(0)
	}

	if os.Args[1] == "list" {
		binary := os.Args[2]
		list(binary)
	} else {
		binary := os.Args[1]
		versionRequirement := os.Args[2]
		resolve(binary, versionRequirement)
	}
}

func resolve(binary string, versionRequirement string) {
	// special-case this string since nodebin does as well and some users use it
	if versionRequirement == "latest" {
		versionRequirement = "*"
	}

	if binary == "node" {
		objects, err := listS3Objects("heroku-nodebin", "node")
		if err != nil {
			fmt.Println(err)
			os.Exit(1)
		}
		result, err := resolveNode(objects, getPlatform(), versionRequirement)
		if err != nil {
			fmt.Println(err)
			os.Exit(1)
		}
		if result.matched {
			fmt.Printf("%s %s\n", result.release.version.String(), result.release.url)
		} else {
			fmt.Println("No result")
			os.Exit(1)
		}
	} else if binary == "yarn" {
		objects, err := listS3Objects("heroku-nodebin", "yarn")
		if err != nil {
			fmt.Println(err)
			os.Exit(1)
		}
		result, err := resolveYarn(objects, versionRequirement)
		if err != nil {
			fmt.Println(err)
			os.Exit(1)
		}
		if result.matched {
			fmt.Printf("%s %s\n", result.release.version.String(), result.release.url)
		} else {
			fmt.Println("No result")
			os.Exit(1)
		}
	}
}

func list(binary string) {
	platform := getPlatform()
	objects, err := listS3Objects("heroku-nodebin", binary)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	for _, obj := range objects {
		release, err := parseObject(obj.Key)
		if err != nil {
			continue
		}

		// ignore any releases that are not for the given platform
		// unless the platform is empty (for yarn)
		if release.platform != platform && release.platform != "" {
			continue
		}

		if release.stage == "release" {
			fmt.Printf("%s %s\n", release.version.String(), release.url)
		}
	}
}

func printUsage() {
	fmt.Println("resolve-version BINARY VERSION_REQUIREMENT")
	fmt.Println("resolve-version list BINARY")
}

func getPlatform() string {
	if runtime.GOOS == "darwin" {
		return "darwin-x64"
	}
	return "linux-x64"
}

func resolveNode(objects []s3Object, platform string, versionRequirement string) (matchResult, error) {
	releases := []release{}
	staging := []release{}

	for _, obj := range objects {
		release, err := parseObject(obj.Key)
		if err != nil {
			continue
		}

		// ignore any releases that are not for the given platform
		if release.platform != platform {
			continue
		}

		if release.stage == "release" {
			releases = append(releases, release)
		} else {
			staging = append(staging, release)
		}
	}

	result, err := matchReleaseSemver(releases, versionRequirement)
	if err != nil {
		return matchResult{}, err
	}

	// In order to accomodate integrated testing of staged Node binaries before they are
	// released broadly, there is a special case where:
	//
	// - if there is no match to a Node binary AND
	// - an exact version of a binary in `node/staging` is present
	//
	// the staging binary is used
	if result.matched == false {
		stagingResult := matchReleaseExact(staging, versionRequirement)
		if stagingResult.matched {
			return stagingResult, nil
		}
	}

	return result, nil
}

func resolveYarn(objects []s3Object, versionRequirement string) (matchResult, error) {
	releases := []release{}

	for _, obj := range objects {
		release, err := parseObject(obj.Key)
		if err != nil {
			continue
		}

		releases = append(releases, release)
	}

	return matchReleaseSemver(releases, versionRequirement)
}

func matchReleaseSemver(releases []release, versionRequirement string) (matchResult, error) {
	constraints, err := semver.ParseRange(versionRequirement)
	if err != nil {
		return matchResult{}, err
	}

	filtered := []release{}
	for _, release := range releases {
		if constraints(release.version) {
			filtered = append(filtered, release)
		}
	}

	versions := make([]semver.Version, len(filtered))
	for i, rel := range filtered {
		versions[i] = rel.version
	}

	coll := semver.Versions(versions)
	sort.Sort(coll)

	if len(coll) == 0 {
		return matchResult{
			versionRequirement: versionRequirement,
			release:            release{},
			matched:            false,
		}, nil
	}

	resolvedVersion := coll[len(coll)-1]

	for _, rel := range filtered {
		if rel.version.Equals(resolvedVersion) {
			return matchResult{
				versionRequirement: versionRequirement,
				release:            rel,
				matched:            true,
			}, nil
		}
	}
	return matchResult{}, errors.New("Unknown error")
}

func matchReleaseExact(releases []release, version string) matchResult {
	for _, release := range releases {
		if release.version.String() == version {
			return matchResult{
				versionRequirement: version,
				release:            release,
				matched:            true,
			}
		}
	}
	return matchResult{
		versionRequirement: version,
		release:            release{},
		matched:            false,
	}
}

// Parses an S3 key into a struct of information about that release
// Example input: node/release/linux-x64/node-v6.2.2-linux-x64.tar.gz
func parseObject(key string) (release, error) {
	nodeRegex := regexp.MustCompile("node\\/([^\\/]+)\\/([^\\/]+)\\/node-v([0-9]+\\.[0-9]+\\.[0-9]+)-([^.]*)(.*)\\.tar\\.gz")
	yarnRegex := regexp.MustCompile("yarn\\/([^\\/]+)\\/yarn-v([0-9]+\\.[0-9]+\\.[0-9]+)\\.tar\\.gz")

	if nodeRegex.MatchString(key) {
		match := nodeRegex.FindStringSubmatch(key)
		version, err := semver.Make(match[3])
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
		version, err := semver.Make(match[2])
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
