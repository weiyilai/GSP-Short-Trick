

gcloud auth list

export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
export REGION="${ZONE%-*}"
gcloud config set compute/region $REGION


gcloud services enable \
container.googleapis.com \
clouddeploy.googleapis.com \
artifactregistry.googleapis.com \
cloudbuild.googleapis.com



sleep 15 


gcloud projects add-iam-policy-binding $PROJECT_ID \
--member=serviceAccount:$(gcloud projects describe $PROJECT_ID \
--format="value(projectNumber)")-compute@developer.gserviceaccount.com \
--role="roles/clouddeploy.jobRunner"

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member=serviceAccount:$(gcloud projects describe $PROJECT_ID \
--format="value(projectNumber)")-compute@developer.gserviceaccount.com \
--role="roles/container.developer"


gcloud artifacts repositories create cicd-challenge \
--description="Image registry for tutorial web app" \
--repository-format=docker \
--location=$REGION


gcloud container clusters create cd-staging --node-locations=$ZONE --num-nodes=1 --async
gcloud container clusters create cd-production --node-locations=$ZONE --num-nodes=1 --async




cd ~/
git clone https://github.com/GoogleCloudPlatform/cloud-deploy-tutorials.git
cd cloud-deploy-tutorials
git checkout c3cae80 --quiet
cd tutorials/base


envsubst < clouddeploy-config/skaffold.yaml.template > web/skaffold.yaml
cat web/skaffold.yaml


cd web
skaffold build --interactive=false \
--default-repo $REGION-docker.pkg.dev/$DEVSHELL_PROJECT_ID/cicd-challenge \
--file-output artifacts.json
cd ..



cp clouddeploy-config/delivery-pipeline.yaml.template clouddeploy-config/delivery-pipeline.yaml
sed -i "s/targetId: staging/targetId: cd-staging/" clouddeploy-config/delivery-pipeline.yaml
sed -i "s/targetId: prod/targetId: cd-production/" clouddeploy-config/delivery-pipeline.yaml
sed -i "/targetId: test/d" clouddeploy-config/delivery-pipeline.yaml


gcloud config set deploy/region $REGION
cp clouddeploy-config/delivery-pipeline.yaml.template clouddeploy-config/delivery-pipeline.yaml
sed -i "s/targetId: staging/targetId: cd-staging/" clouddeploy-config/delivery-pipeline.yaml
sed -i "s/targetId: prod/targetId: cd-production/" clouddeploy-config/delivery-pipeline.yaml
sed -i "/targetId: test/d" clouddeploy-config/delivery-pipeline.yaml
gcloud beta deploy apply --file=clouddeploy-config/delivery-pipeline.yaml

gcloud beta deploy delivery-pipelines describe web-app

sleep 5

CLUSTERS=("cd-production" "cd-staging")

for cluster in "${CLUSTERS[@]}"; do
  status=$(gcloud container clusters describe "$cluster" --format="value(status)")
  
  while [ "$status" != "RUNNING" ]; do
    echo "Waiting for $cluster to be RUNNING..."

    sleep 15
    status=$(gcloud container clusters describe "$cluster" --format="value(status)")
  done
  
  echo "$cluster is now running, please subscribe to techcps! [https://www.youtube.com/@techcps]..."
  
done


CONTEXTS=("cd-staging" "cd-production" )
for CONTEXT in ${CONTEXTS[@]}
do
    gcloud container clusters get-credentials ${CONTEXT} --region ${REGION}
    kubectl config rename-context gke_${PROJECT_ID}_${REGION}_${CONTEXT} ${CONTEXT}
done

for CONTEXT in ${CONTEXTS[@]}
do
    kubectl --context ${CONTEXT} apply -f kubernetes-config/web-app-namespace.yaml
done

envsubst < clouddeploy-config/target-staging.yaml.template > clouddeploy-config/target-cd-staging.yaml
envsubst < clouddeploy-config/target-prod.yaml.template > clouddeploy-config/target-cd-production.yaml

sed -i "s/staging/cd-staging/" clouddeploy-config/target-cd-staging.yaml
sed -i "s/prod/cd-production/" clouddeploy-config/target-cd-production.yaml


for CONTEXT in ${CONTEXTS[@]}
do
    envsubst < clouddeploy-config/target-$CONTEXT.yaml.template > clouddeploy-config/target-$CONTEXT.yaml
    gcloud beta deploy apply --file clouddeploy-config/target-$CONTEXT.yaml
done


gcloud beta deploy releases create web-app-001 \
--delivery-pipeline web-app \
--build-artifacts web/artifacts.json \
--source web/




gcloud beta deploy rollouts list \
--delivery-pipeline web-app \
--release web-app-001


while true; do
  status=$(gcloud beta deploy rollouts list --delivery-pipeline web-app --release web-app-001 --format="value(state)" | head -n 1)
  if [ "$status" == "SUCCEEDED" ]; then
    break
  fi
  echo "it's creating now, please wait, subscribe to techcps! [https://www.youtube.com/@techcps]..."
  sleep 15
done


gcloud beta deploy releases promote \
--delivery-pipeline web-app \
--release web-app-001 \
--quiet


while true; do
  status=$(gcloud beta deploy rollouts list --delivery-pipeline web-app --release web-app-001 --format="value(state)" | head -n 1)
  if [ "$status" == "PENDING_APPROVAL" ]; then
    break
  fi
  echo "it's creating now, please wait & subscribe to techcps! [https://www.youtube.com/@techcps]..."
  sleep 15
done


gcloud beta deploy rollouts approve web-app-001-to-cd-production-0001 \
--delivery-pipeline web-app \
--release web-app-001 \
--quiet


while true; do
  status=$(gcloud beta deploy rollouts list --delivery-pipeline web-app --release web-app-001 --format="value(state)" | head -n 1)
  if [ "$status" == "SUCCEEDED" ]; then
    break
  fi
  echo "it's creating now, please wait & subscribe to techcps! [https://www.youtube.com/@techcps]..."
  sleep 15
done

gcloud services enable cloudbuild.googleapis.com

cd ~/
git clone https://github.com/GoogleCloudPlatform/cloud-deploy-tutorials.git
cd cloud-deploy-tutorials
git checkout c3cae80 --quiet
cd tutorials/base

envsubst < clouddeploy-config/skaffold.yaml.template > web/skaffold.yaml
cat web/skaffold.yaml

cd web
skaffold build --interactive=false \
--default-repo $REGION-docker.pkg.dev/$DEVSHELL_PROJECT_ID/cicd-challenge \
--file-output artifacts.json
cd ..

gcloud beta deploy releases create web-app-002 \
--delivery-pipeline web-app \
--build-artifacts web/artifacts.json \
--source web/


while true; do
  status=$(gcloud beta deploy rollouts list --delivery-pipeline web-app --release web-app-002 --format="value(state)" | head -n 1)
  if [ "$status" == "SUCCEEDED" ]; then
    break
  fi
  echo "it's creating now, please wait & subscribe to techcps! [https://www.youtube.com/@techcps]..."
  sleep 15
done

gcloud deploy targets rollback cd-staging \
   --delivery-pipeline=web-app \
   --quiet



