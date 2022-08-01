echo "Running yarn and building all packages..."
yarn
yarn build:all
echo "Build done."

echo "Docker: building sequencer-publisher and sequencer-subscriber images..."
docker build --tag sequencer-publisher:latest --file ./docker/sequencer/publisher/Dockerfile .
docker build --tag sequencer-subscriber:latest --file ./docker/sequencer/subscriber/Dockerfile .

echo "Docker: building router-publisher and router-subscriber images..."
docker build --tag router-publisher:latest --file ./docker/router/publisher/Dockerfile .
docker build --tag router-subscriber:latest --file ./docker/router/subscriber/Dockerfile .

echo "Docker: building relayer image..."
docker build --tag relayer:latest --file ./docker/relayer/Dockerfile .

echo "Docker: building lighthouse image..."
docker build --tag lighthouse:latest --file ./docker/lighthouse/Dockerfile .

echo "Docker: building cartographer-transfers and cartographer-routers images..."
docker build --tag cartographer-transfers:latest --file ./docker/cartographer/transfers/Dockerfile .
docker build --tag cartographer-routers:latest --file ./docker/cartographer/routers/Dockerfile .
