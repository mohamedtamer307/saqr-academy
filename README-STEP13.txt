إصلاح فتح الكورس وتشغيل الفيديو - SAQR Academy

1) استبدل course.html و watch.html و dashboard.html في مشروعك.
2) ضع get-video-url.ts داخل Supabase Edge Function باسم:
   get-video-url/index.ts
3) انشر الـ Edge Function.
4) تأكد أن Storage bucket اسمه academy-videos وهو Private.
5) تأكد أن المستخدم لديه subscription status=active و ends_at في المستقبل.
6) تأكد أن plan_courses يحتوي على plan_id الخاص بالاشتراك و course_id للكورس.
7) الفيديو الذي رفعته سابقًا لا يحتاج لإعادة رفعه.

مهم:
- لا تضع SUPABASE_SERVICE_ROLE_KEY داخل HTML أو JavaScript الخاص بالموقع.
- المفتاح Service Role يجب أن يبقى داخل Edge Function فقط.
