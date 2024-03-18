function handler () {
    echo $(cat /tmp/payload)
    jq -r '.Records[0].body' < /tmp/payload > /tmp/Sample.txt
    head -n -8 /tmp/Sample.txt > /tmp/Sample.java
    echo $(cat /tmp/Sample.java)
    echo $(cat /tmp/Sample.txt)
    code=$(cat /tmp/Sample.java)
    qid=$(grep -oE 'questionMasterId:[0-9]+' /tmp/Sample.txt | cut -d ':' -f 2)
    echo "qid is $qid"
    testcase_timeout=$(grep -oE 'testcaseTimeout:[0-9]+' /tmp/Sample.txt | cut -d ':' -f 2)
    noOfTestCases=$(grep -oE 'noOfTestCases:[0-9]+' /tmp/Sample.txt | cut -d ':' -f 2)
    verdictId=$(grep -oE 'verdictId:[0-9]+' /tmp/Sample.txt | cut -d ':' -f 2)
    noOfTestCases=${noOfTestCases:-4}
    testcase_timeout=${testcase_timeout:-2}

    if javac -d /tmp /tmp/Sample.java 2> /tmp/CompilationError.txt; then
        echo "Compilation successful"
        i=1
        json="["
        while [ $i -le $noOfTestCases ]
        do
            time -f "Time(s): %e Memory(Kb): %M " timeout $testcase_timeout java -cp /tmp Sample < /mnt/efs/$qid/input$i.txt > /tmp/useroutput$i 2> /tmp/error$i
            cat /tmp/useroutput$i
            cat /mnt/efs/$qid/output$i.txt

            json="${json} {\"name\": \"Testcase - $i\" ,"
            json="${json} \"input\": \"$(cat /mnt/efs/$qid/input$i.txt)\" ,"
            json="${json} \"expectedoutput\": \"$(cat /mnt/efs/$qid/output$i.txt)\" ,"
            json="${json} \"actualoutput\": \"$(cat /tmp/useroutput$i)\" ,"

            # Check if the testcase passed
            if cmp -s /tmp/useroutput$i /mnt/efs/$qid/output$i.txt; then
                val=$(tail -n1 /tmp/error$i | grep -o -E '[0-9]+' | head -n1)
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
                json="${json} \"metric\":\"$(tail -n1 /tmp/error$i)\"},"
            else
                echo "Testcase - $i failed because user output does not match with expected output"
                json="${json} \"passed\": false ,"
                json="${json} \"message\":\"User output does not match with expected output\" ,"
                json="${json} \"metric\":\"$(tail -n1 /tmp/error$i)\"},"
            fi
            i=`expr $i + 1`
        done
        json=${json::-1}
        json="${json}]"
        echo "Response: $json"
        insert_query="UPDATE code_verdict SET is_compile_success = 'true', subjective_answer = '$code', verdict = '$json' , status = 'DONE' , updated_date_time = CURRENT_TIMESTAMP WHERE code_verdict_id = '$verdictId'";

    else
        error=$(cat /tmp/CompilationError.txt)
        echo '{"status": "error", "message": "Compilation failed", "error": "'"$error"'"}'
        error=$(echo "$error" | tr -d "'")
        echo error
        json="[$error]"
        echo "Response: $json"
        insert_query="UPDATE code_verdict SET is_compile_success = 'false', subjective_answer = '$code', verdict = '$json' , status = 'DONE' , updated_date_time = CURRENT_TIMESTAMP WHERE code_verdict_id = '$verdictId'";
    fi
    echo "Connecting and Inserting into db :)"
    echo $insert_query
    PGPASSWORD=${DB_PASSWORD} psql --host=${DB_ENDPOINT} --port=${DB_PORT} --user=${DB_USERNAME} ${DB_NAME} -c "$insert_query";
    echo "inserted :)"
}
