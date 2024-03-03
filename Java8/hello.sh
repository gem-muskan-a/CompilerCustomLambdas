function handler () {
    echo $(cat /tmp/payload)
    jq -r '.Records[0].body' < /tmp/payload > /tmp/Sample.txt
    echo "$(perl -0777 -ne 'print $1 if /"subjectiveAnswer": "(.*?)"/s' /tmp/Sample.txt)" > /tmp/Sample.java
    echo $(cat /tmp/Sample.java)
    
    # Extract values from the body
    userid=$(grep -oP '"candidateId": \K["\d]+' /tmp/Sample.txt) 
    qid=$(grep -oP '"questionMasterId": "\K["\d]+' /tmp/Sample.txt)
    code=$(cat /tmp/Sample.java)
    testid=$(grep -oP '"testId": \K["\d]+' /tmp/Sample.txt)
    timetoans=$(grep -oP '"timeTakenToAnswer": \K["\d]+' /tmp/Sample.txt)
    testcase_timeout=$(grep -oP '"testcaseTimeout": \K["\d]+' /tmp/Sample.txt)
    is_submission=$(grep -oP '"isSubmission": \K[^,]+' /tmp/Sample.txt)
    noOfTestCases=$(grep -oP '"noOfTestCases": \K["\d]+' /tmp/Sample.txt)
    noOfTestCases=${noOfTestCases:-4}
    testcase_timeout=${testcase_timeout:-2}

    if javac -d /tmp /tmp/Sample.java 2> /tmp/CompilationError.txt; then
        echo "Compilation successful"
        i=1
        json="["
        while [ $i -le $noOfTestCases ]
        do
            time -f "Time(s): %e Memory(Kb): %M " timeout 2 java -cp /tmp Sample < /mnt/efs/$qid/input$i > /mnt/efs/$qid/useroutput$i 2> /mnt/efs/$qid/error$i 
            cat /mnt/efs/$qid/useroutput$i
            cat /mnt/efs/$qid/output$i

            json="${json} {\"name\": \"Testcase - $i\" ,"
            json="${json} \"input\": \"$(cat /mnt/efs/$qid/input$i)\" ,"
            json="${json} \"expectedoutput\": \"$(cat /mnt/efs/$qid/output$i)\" ,"
            json="${json} \"actualoutput\": \"$(cat /mnt/efs/$qid/useroutput$i)\" ,"

            # Check if the testcase passed
            if cmp -s /mnt/efs/$qid/useroutput$i /mnt/efs/$qid/output$i; then
                val=$(tail -n1 /mnt/efs/$qid/error$i | grep -o -E '[0-9]+' | head -n1)
                if [ $val -ge $testcase_timeout ]
                then
                    echo "Testcase - $i failed because of exceed time limit"
                    json="${json} \"passed\": false ,"
                    json="${json} ,\"message\":\"Time Limit Exceeded\" ,"
                else
                    echo "Testcase - $i passed"
                    json="${json} \"passed\": true ,"
                    json="${json} ,\"message\":\"OK\" ,"
                fi
                json="${json} \"metric\":\"$(tail -n1 /mnt/efs/$qid/error$i)\"},"
            else
                echo "Testcase - $i failed because user output does not match with expected output"
                json="${json} \"passed\": false ,"
                json="${json} \"message\":\"User output does not match with expected output\" ,"
                json="${json} \"metric\":\"$(tail -n1 /mnt/efs/$qid/error$i)\"},"
            fi
            i=`expr $i + 1`
        done
        json=${json::-1}
        json="${json}]"
        echo "Response: $json"
        insert_query="INSERT INTO code_verdict(candidate_id, created_date_time, is_submission, is_compile_success, language_used, question_master_id, subjective_answer, test_id, time_taken_to_answer, verdict) VALUES ('$userid', CURRENT_TIMESTAMP, '$is_submission', 'true', 'java', '$qid', '$code', '$testid', '$timetoans', '$json')";

    else
        error=$(cat /tmp/CompilationError.txt)
        echo '{"status": "error", "message": "Compilation failed", "error": "'"$error"'"}'
        error=$(echo "$error" | tr -d "'")
        echo error
        json="[$error]"
        echo "Response: $json"
        insert_query="INSERT INTO code_verdict(candidate_id, created_date_time, is_submission, is_compile_success, language_used, question_master_id, subjective_answer, test_id, time_taken_to_answer, verdict) VALUES ('$userid', CURRENT_TIMESTAMP, '$is_submission', 'false', 'java', '$qid', '$code', '$testid', '$timetoans', '$json')";
    fi  
    echo "Connecting and Inserting into db :)"
    psql --host=${DB_ENDPOINT} --port=${DB_PORT} --user=${DB_USERNAME} --password=${DB_PASSWORD} ${DB_NAME} -e "$insert_query";
    echo "inserted :)"
}
