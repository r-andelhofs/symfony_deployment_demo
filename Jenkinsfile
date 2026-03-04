pipeline {
    agent any

    environment {
        // Unique identifiers for this specific build
        NET_NAME   = "net-${env.BUILD_ID}"
        DB_NAME    = "db-${env.BUILD_ID}"
        RABBIT_NAME = "mq-${env.BUILD_ID}"
        APP_NAME   = "app-${env.BUILD_ID}"
        TEST_RUNNER = "tester-${env.BUILD_ID}"
        
        // Database Credentials
        DB_USER     = "symfony"
        DB_PASS     = "secret"
        DB_DATABASE = "app_db"
        
        // Dynamic Port for the Web UI
        TEST_PORT  = "${9000 + (env.BUILD_NUMBER.toInteger() % 1000)}"

        COOKBOOK_REPO = "git@github.com:level27/chef-repo.git"
    }

    stages {
        stage('Setup Network & DB') {
            steps {
                // Create a dedicated network so containers can "see" each other
                sh "docker network create ${NET_NAME}"

                // Start RabbitMQ (Management plugin included for debugging if needed)
                sh "docker run -d --name ${RABBIT_NAME} --network ${NET_NAME} rabbitmq:3-management"
                
                // Spin up MySQL and wait for it to be ready
                sh """
                docker run -d --name ${DB_NAME} --network ${NET_NAME} \
                    -e MYSQL_ROOT_PASSWORD=root \
                    -e MYSQL_DATABASE=${DB_DATABASE} \
                    -e MYSQL_USER=${DB_USER} \
                    -e MYSQL_PASSWORD=${DB_PASS} \
                    mysql:8.0
                """
                echo "Waiting for MySQL to initialize..."
                sleep 15 // Give MySQL a moment to start up
            }
        }

        stage('Build & Migrations') {
            steps {
                script {
                    // Build your Symfony Image
                    def symfonyImage = docker.build("${APP_NAME}:latest")
                    def uId = sh(script: 'id -u', returnStdout: true).trim()
                    def gId = sh(script: 'id -g', returnStdout: true).trim()

                    // Fix permissions for Symfony
                    sh """
                    docker run --rm --network ${NET_NAME} --volume ".:/var/www/html" --user ${uId}:${gId} -e DATABASE_URL="mysql://${DB_USER}:${DB_PASS}@${DB_NAME}:3306/${DB_DATABASE}?serverVersion=8.0" \
                        ${APP_NAME}:latest bash -c "composer update && php bin/console doctrine:schema:update --force && php bin/console doctrine:fixtures:load --append"
                    """
                }
            }
        }

        stage('Deploy Ephemeral App') {
            steps {
                script{
                    def uId = sh(script: 'id -u', returnStdout: true).trim()
                    def gId = sh(script: 'id -g', returnStdout: true).trim()
                    // Run the web server
                    sh """
                    docker run -d --name ${APP_NAME} --volume ".:/var/www/html" --user ${uId}:${gId} --network ${NET_NAME} -p ${TEST_PORT}:8000 \
                        -e DATABASE_URL="mysql://${DB_USER}:${DB_PASS}@${DB_NAME}:3306/${DB_DATABASE}?serverVersion=8.0" \
                        ${APP_NAME}:latest php -S 0.0.0.0:8000 -t public
                    """
                    
                    echo "------------------------------------------------------------"
                    echo "SUCCESS: Symfony is live at http://172.23.21.16:${TEST_PORT}"
                    echo "Database Host inside network: ${DB_NAME}"
                    echo "------------------------------------------------------------"
                }
            }
        }

        stage('External Integration Tests') {
            steps {
                withCredentials([string(credentialsId: 'GITHUB_SSH_KEY', variable: 'SSH_KEY')]) {
                    script {
                        // Run a full Ubuntu 24.04 container to perform tests against the network
                        sh """
                        docker run -dit --name ${TEST_RUNNER} --network ${NET_NAME} \
                        -e SSH_KEY="${SSH_KEY}" ubuntu:24.04
                        """

                        sh """
                        docker exec -i ${TEST_RUNNER} bash <<'EOF'
                            set -e
                            echo "--- 1. Installing System Dependencies ---"
                            apt-get update && apt-get install -y curl git ssh-client

                            echo "--- 2. Setting up SSH for Private Repo ---"
                            mkdir -p ~/.ssh
                            echo "${SSH_KEY}" > ~/.ssh/id_rsa
                            chmod 600 ~/.ssh/id_rsa
                            ssh-keyscan github.com >> ~/.ssh/known_hosts

                            echo "--- 3. Installing Chef (Cinc-Client) ---"
                            # Cinc is the fully open-source distribution of Chef Infra Client
                            curl -L https://omnitruck.cinc.sh/install.sh | bash

                            echo "--- 4. Cloning Private Cookbooks ---"
                            git clone ${COOKBOOK_REPO} /tmp/chef-repo
                            cd /tmp/chef-repo
                            git checkout develop

                            echo "--- 5. Executing Chef-Solo ---"
                            # We create a minimal dna.json to tell Chef what to run
                            echo '{"run_list": ["recipe[my_test_suite::default]"]}' > /tmp/dna.json
                            
                            # Run Chef
                            cinc-solo -j /tmp/dna.json --base-repo-path /tmp/chef-repo

                            echo "--- 6. Running Application Tests ---"
                            # Now that Chef has configured the environment (installed tools, etc.)
                            curl -f http://${APP_NAME}:8000/health
EOF
                        """
                    }
                }
            }
        }

        stage('Manual Review') {
            steps {
                // This will pause the pipeline and wait for a user to click "Proceed" or "Abort"
                input message: "Review the application at http://172.23.21.16:${TEST_PORT}. Click 'Proceed' to kill the environment.", ok: "Proceed"
            }
        }
    }

    post {
        always {
            echo "Cleaning up ephemeral environment..."
            // Remove containers and the network regardless of success/failure/manual stop
            sh "docker stop ${APP_NAME} ${DB_NAME} ${TEST_RUNNER} ${RABBIT_NAME} || true"
            sh "docker rm ${APP_NAME} ${DB_NAME} ${TEST_RUNNER} ${RABBIT_NAME} || true"
            sh "docker network rm ${NET_NAME} || true"
            sh "docker rmi ${APP_NAME}:latest || true"
        }
    }
}