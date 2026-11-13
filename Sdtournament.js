    function formValidation()  
    {  
	var utournament = document.registration.tournament;  
	var ufullname = document.registration.fullname;  
	var uschoolname = document.registration.schoolname;  
	var uclass = document.registration.classstudying;  
    
	var uparentname = document.registration.parentname;  
	var uemail = document.registration.parentemailid;  
	var ucontact = document.registration.parentcontactnumber;
	var chess=document.registration.chesscategories;
	var fida=document.registration.fidaid;
	var cdca=document.registration.cdcaid;

	if(utournament.value == "Default")  
	{  
	alert('Select your Tournament');  
		document.registration.tournament.focus();  
	  return false;  
	} 
	
	if(utournament.value == "2")  
	{  
		if(chess.value=="")
		{
		alert('Select your Chess Tournament Category');  
		document.registration.chesscategories.focus();  
		  return false;  
		}  				
		if(fida.value=="")
		{
		alert('Enter your FIDA id');  
		document.registration.fidaid.focus();  
		  return false;  
		}  	
		
		if(cdca.value=="")
		{
		alert('Enter your CDCA id');  
		document.registration.cdcaid.focus();  
		  return false;  
		}  
		
	
	}
	
	if (ufullname.value=="")  
    {  
    alert('Kindly enter your full name. Avoid Numerical characters.');  
    ufullname.focus();  
    return false;  
	}
	
	if(uschoolname.value == "")  
	{  
	alert('Kindly enter your schoolname');  
	uschoolname.focus();  
	return false;  
	}  
	
	if(uclass.value == "Default")  
	{  
	alert('Select your Class');  
		document.registration.classstudying.focus();  
	  return false;  
	}  
 
	if(uparentname.value=="")  
    {  
    alert('Kindly enter your Parents name.');  
    uparentname.focus();  
    return false; 
    }  
	
	if(uemail.value=="")  
    {  
    alert("Enter your parent email address!");  
    uemail.focus();  
    return false;
    }  
       
    if(ucontact.value=="")  
    {  
			alert(" Kindly enter your contact number");  
			ucontact.focus();
            return false;  
     }  
            
 
	}
	
	