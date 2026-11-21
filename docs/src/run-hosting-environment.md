# Hosting Environment–specific Guides

PostgSail runs anywhere Docker runs. Pick the guide that matches where you host it:

| Guide                                      | Use it when                                                                  |
| ------------------------------------------ | ---------------------------------------------------------------------------- |
| [Linux Server](run-with-docker.md)         | You start from a fresh Linux server and need to install Docker first.        |
| [Docker Compose](run-with-docker-compose.md) | You run PostgSail on a single machine. This is the recommended setup.      |
| [Kubernetes](run-with-kubernetes.md)       | You deploy to a Kubernetes cluster, such as MicroK8s or kind.                |
| [AWS](run-with-aws.md)                     | You host PostgSail on an AWS instance.                                       |

Whichever you choose, set your environment variables first: see [Environment Variables](env-vars.md). To expose PostgSail over HTTPS, put it behind a [reverse proxy](run-with-reverse-proxy.md).
