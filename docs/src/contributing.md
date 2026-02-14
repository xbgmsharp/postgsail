# Contributing

Contributions are what make the open source community such an amazing place to be learn, inspire, and create. Any contributions you make are **greatly appreciated**.

* If you have suggestions for features, feel free to [open an issue](https://github.com/xbgmsharp/postgsail/issues/new) to discuss it, or directly create a pull request with necessary changes.
* Please make sure you check your spelling and grammar.
* Create individual PR for each suggestion.
* Please also read through the [Code Of Conduct](https://github.com/xbgmsharp/postgsail/blob/main/CODE_OF_CONDUCT.md) before posting your first idea as well.

## docker

Install [docker](https://docs.docker.com/get-docker/) and [docker-compose](https://docs.docker.com/compose/)

## Git setup

The recommended setup for both core and casual contributors is to **always** create a fork
of the primary repo under their own account. The local repo should have two remotes: `upstream` pointing to the primary `maplibre/martin` repo, and `origin` pointing to the user's own fork. The `main` branch should track `upstream/main`, but all new work will be pushed to `origin` and PRs will be created from there.

<details><summary>Rationale for this setup (click to expand)</summary>

<small>This rationale was copied from [a post](https://gist.github.com/nyurik/4e299ad832fd2dd43d2b27191ed3ec30) by Yuri</small>

Open source contribution is both a technical and a social phenomenon.
Any FOSS project naturally has a "caste system" - a group
of contributors with extensive rights vs everyone else. Some of this separation
is necessary - core contributors have deeper knowledge of the code, share vision,
and trust each other.

Core contributors have one more right that others do not -- they can create repository branches.
Thus, they can contribute "locally" - by pushing proposed changes to the primary repository's work branches,
and create "local" pull requests inside the same repo.  This is different from others,
who can contribute only from their own forks.

There is little difference between creating pull requests from one's own fork and from the primary repo,
and there are a few reasons why core contributors should **never** do it from the primary repo:

* it ensures that casual contributors always run the same CI as core contributors. If contribution process breaks, it will affect everyone, and will get fixed faster.
* it puts everyone on the same leveled playing field, reducing the "caste system" effect, making the project feel more welcoming to new contributors
* it ensures that the primary repo only has maintained branches (e.g. `main` and `v1.x`),
  not a bunch of PR branches whose ownership and work status is unclear to everyone

In the martin repository, we follow this and have a branch protection rule that prevents core contributors from creating pull requests from the primary repo.

</details>

